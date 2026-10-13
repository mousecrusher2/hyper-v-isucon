#requires -Version 7.4

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
        [ValidateRange(0,[long]::MaxValue)][long]$MaximumIOPS = 0,
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
    Set-VMProcessor -VM $taskVM -HwThreadCountPerCore 2
    Get-VMHardDiskDrive -VM $taskVM | Set-VMHardDiskDrive -MaximumIOPS $MaximumIOPS
    Set-VMMemory -VM $taskVM -DynamicMemoryEnabled $false
    Get-VMNetworkAdapter -VM $taskVM | Rename-VMNetworkAdapter -NewName uplink
    Add-VMNetworkAdapter -VM $taskVM -Name $InternalAdapterName -SwitchName $InternalSwitchName
    Disable-VMIntegrationService -VM $taskVM -Name VSS
    Disable-VMConsoleSupport -VMName $Name
    foreach ($taskNic in Get-VMNetworkAdapter -VM $taskVM) {
        do {
            $taskMac = Get-RandomMACAddress
            $taskExistingMacs = @((Get-VM | Get-VMNetworkAdapter).MacAddress) + @((Get-VMNetworkAdapter -ManagementOS).MacAddress)
        } while ($taskMac -in $taskExistingMacs)
        Set-VMNetworkAdapter -VMNetworkAdapter $taskNic -StaticMacAddress $taskMac
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
    Set-VMFirmware -VM $VM -EnableSecureBoot On -SecureBootTemplate MicrosoftUEFICertificateAuthority -FirstBootDevice $taskDVD
}

function Set-VMDiskBoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$VM)
    Set-VMFirmware -VM $VM -FirstBootDevice (Get-VMHardDiskDrive -VM $VM -ErrorAction Stop) -ErrorAction Stop
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
