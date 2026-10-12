#requires -Version 7.3

function Get-RandomMACAddress {
    $taskMacBytes = [Security.Cryptography.RandomNumberGenerator]::GetBytes(6)
    $taskMacBytes[0] = ($taskMacBytes[0] -band 0xFC) -bor 0x02
    [Convert]::ToHexString($taskMacBytes)
}

function New-UnattendedVM {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$SwitchName,
        [Parameter(Mandatory)][string]$InternalSwitchName,
        [Parameter(Mandatory)][long]$MemoryBytes,
        [Parameter(Mandatory)][int]$ProcessorCount,
        [Parameter(Mandatory)][long]$DiskSizeBytes,
        [string]$InternalAdapterName = 'internal'
    )
    if (Get-VM -Name $Name -ErrorAction SilentlyContinue) { throw "VM $Name は既に存在します。" }
    if (Test-Path -LiteralPath $Path) { throw "$Path は既に存在します。" }
    Get-VMSwitch -Name $SwitchName -ErrorAction Stop | Out-Null
    if ($SwitchName -eq $InternalSwitchName) { throw 'インターネット用と固定IP用には別のスイッチを指定してください。' }
    if ((Get-VMSwitch -Name $InternalSwitchName -ErrorAction Stop).SwitchType -ne 'Internal') {
        throw '固定IP用のInternal Switchを指定してください。'
    }
    New-Item -ItemType Directory -Path $Path | Out-Null
    $taskDisk = Join-Path $Path 'disk.vhdx'
    New-VHD -Path $taskDisk -Dynamic -SizeBytes $DiskSizeBytes -BlockSizeBytes 1MB -LogicalSectorSizeBytes 4096 -PhysicalSectorSizeBytes 4096 | Out-Null
    $taskVM = New-VM -Name $Name -Generation 2 -MemoryStartupBytes $MemoryBytes -VHDPath $taskDisk -SwitchName $SwitchName -Path $Path
    Set-VM -VM $taskVM -ProcessorCount $ProcessorCount -AutomaticCheckpointsEnabled $false -CheckpointType Disabled -AutomaticStartAction Nothing -AutomaticStopAction ShutDown
    Set-VMMemory -VM $taskVM -DynamicMemoryEnabled $false
    Get-VMNetworkAdapter -VM $taskVM | Rename-VMNetworkAdapter -NewName uplink
    Add-VMNetworkAdapter -VM $taskVM -Name $InternalAdapterName -SwitchName $InternalSwitchName
    Disable-VMIntegrationService -VM $taskVM -Name VSS
    Disable-VMConsoleSupport -VMName $Name
    Set-VMFirmware -VM $taskVM -EnableSecureBoot On -SecureBootTemplate MicrosoftUEFICertificateAuthority

    # Serialize allocation across build workers so the host-wide check and assignment are atomic.
    $taskMacLock = [Threading.Mutex]::new($false, 'Global\HyperV-RandomMACAddress')
    $taskLocked = $false
    try {
        try { $taskLocked = $taskMacLock.WaitOne([TimeSpan]::FromSeconds(30)) }
        catch [Threading.AbandonedMutexException] { $taskLocked = $true }
        if (-not $taskLocked) { throw 'MACアドレスの割り当て待ちがタイムアウトしました。' }
        foreach ($taskNic in Get-VMNetworkAdapter -VM $taskVM) {
            do {
                $taskMac = Get-RandomMACAddress
                $taskExistingMacs = @((Get-VM | Get-VMNetworkAdapter).MacAddress) + @((Get-VMNetworkAdapter -ManagementOS).MacAddress)
            } while ($taskMac -in $taskExistingMacs)
            Set-VMNetworkAdapter -VMNetworkAdapter $taskNic -StaticMacAddress $taskMac
        }
    } finally {
        if ($taskLocked) { $taskMacLock.ReleaseMutex() }
        $taskMacLock.Dispose()
    }
    $taskVM
}

function Mount-VMDvd {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$VM,
        [Parameter(Mandatory)][string]$InstallerIsoPath,
        [Parameter(Mandatory)][string]$SeedIsoPath
    )
    $taskDVD = Add-VMDvdDrive -VM $VM -Path $InstallerIsoPath -Passthru
    Add-VMDvdDrive -VM $VM -Path $SeedIsoPath
    Set-VMFirmware -VM $VM -FirstBootDevice $taskDVD
}

function Dismount-VMDvd {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$VM)
    Get-VMDvdDrive -VM $VM | Remove-VMDvdDrive
    Set-VMFirmware -VM $VM -FirstBootDevice (Get-VMHardDiskDrive -VM $VM)
}

function Wait-VMState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$VMName,
        [Parameter(Mandatory)][string]$State,
        [ValidateRange(1,120)][int]$TimeoutMinutes = 45
    )
    $taskDeadline = (Get-Date).AddMinutes($TimeoutMinutes)
    while ((Get-VM -Name $VMName -ErrorAction Stop).State -ne $State) {
        if ((Get-Date) -ge $taskDeadline) {
            throw "VM $VMName の状態 $State 待ちがタイムアウトしました。VMとディスクを残しています。"
        }
        Start-Sleep -Seconds 3
    }
}

function Set-VMResourceProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$VM,
        [Parameter(Mandatory)][ValidateRange(1,1024)][int]$ProcessorCount,
        [Parameter(Mandatory)][ValidateSet(0,1,2)][int]$HwThreadCountPerCore,
        [Parameter(Mandatory)][ValidateRange(0,[long]::MaxValue)][long]$MaximumIOPS
    )
    $taskVM = Get-VM -Name $VM.Name -ErrorAction Stop
    if ($taskVM.State -notin 'Off', 'Running') { throw '停止中または起動中のVMを指定してください。' }
    $taskProcessor = Get-VMProcessor -VM $taskVM
    $taskChangeCPU = $taskProcessor.Count -ne $ProcessorCount -or $taskProcessor.HwThreadCountPerCore -ne $HwThreadCountPerCore
    $taskRestart = $taskChangeCPU -and $taskVM.State -eq 'Running'
    if ($taskRestart) {
        Stop-VM -VM $taskVM
        Wait-VMState -VMName $taskVM.Name -State Off -TimeoutMinutes 5
    }
    if ($taskChangeCPU) { Set-VMProcessor -VM $taskVM -Count $ProcessorCount -HwThreadCountPerCore $HwThreadCountPerCore }
    Get-VMHardDiskDrive -VM $taskVM | Set-VMHardDiskDrive -MaximumIOPS $MaximumIOPS
    if ($taskRestart) { Start-VM -VM $taskVM }
}
