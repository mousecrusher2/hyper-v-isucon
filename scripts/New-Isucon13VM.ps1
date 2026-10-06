#requires -Version 7.3
#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$IsoPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [ValidateCount(3,3)][ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$')][string[]]$ApplicationName = @('isucon13-app01', 'isucon13-app02', 'isucon13-app03'),
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$')][string]$BenchmarkerName = 'isucon13-bench',
    [string]$SwitchName = 'Default Switch',
    [string]$InternalSwitchName = 'ISUCON13',
    [string]$NetworkPrefix = '192.168.13.0/24',
    [Alias('MemoryMaximumBytes')][ValidateRange(2GB, [long]::MaxValue)][long]$MemoryBytes = 4GB,
    [ValidateRange(1,1024)][int]$ProcessorCount = 2,
    [Alias('BenchmarkerMemoryMaximumBytes')][ValidateRange(2GB, [long]::MaxValue)][long]$BenchmarkerMemoryBytes = 4GB,
    [ValidateRange(1,1024)][int]$BenchmarkerProcessorCount = 8,
    [ValidateRange(5,120)][int]$TimeoutMinutes = 45
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandArgumentPassing = 'Standard'
$PSNativeCommandUseErrorActionPreference = $false
. "$PSScriptRoot\IsoContainer.ps1"
$taskOutputRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
$taskMachines = @(
    foreach ($taskVMName in $ApplicationName) {
        [pscustomobject]@{ Name = $taskVMName; Role = 'application'; Memory = $MemoryBytes; CPUs = $ProcessorCount }
    }
    [pscustomobject]@{ Name = $BenchmarkerName; Role = 'benchmarker'; Memory = $BenchmarkerMemoryBytes; CPUs = $BenchmarkerProcessorCount }
)
if ($taskMachines.Count -ne @($taskMachines.Name | Sort-Object -Unique).Count) { throw 'VM名が重複しています。' }
foreach ($taskVMName in $taskMachines.Name) {
    if (Get-VM -Name $taskVMName -ErrorAction SilentlyContinue) { throw "VM $taskVMName は既に存在します。" }
    $taskVmDir = Join-Path $taskOutputRoot "vm\$taskVMName"
    if (Test-Path -LiteralPath $taskVmDir) { throw "$taskVmDir は既に存在します。" }
}
$taskIso = (Resolve-Path -LiteralPath $IsoPath).Path
Get-VMSwitch -Name $SwitchName -ErrorAction Stop | Out-Null
if ($SwitchName -eq $InternalSwitchName) { throw 'インターネット用と固定IP用には別のスイッチを指定してください。' }
$taskInstallIso = Join-Path $taskOutputRoot "vm\install-$([guid]::NewGuid()).iso"
# Prepare the shared key before starting workers.
$taskKey = Join-Path $taskOutputRoot 'ssh\id_ed25519'
New-Item -ItemType Directory -Path (Split-Path -Parent $taskKey) -Force | Out-Null
if (-not (Test-Path -LiteralPath $taskKey)) {
    & ssh-keygen -q -t ed25519 -N '' -C 'hyper-isucon-local' -f $taskKey
    if ($LASTEXITCODE -ne 0) { throw 'SSH鍵の生成に失敗しました。' }
}

$taskJobs = @()
$taskIsoContainer = $null
try {
    $taskIsoLog = Join-Path $taskOutputRoot "logs\iso-$([IO.Path]::GetFileNameWithoutExtension($taskInstallIso)).log"
    $taskIsoContainer = Start-IsoContainer -OutputPath (Join-Path $taskOutputRoot 'vm') -SourceIsoPath $taskIso -LogPath $taskIsoLog
    & "$PSScriptRoot\New-AutoinstallIso.ps1" -SourceIsoPath $taskIso -IsoPath $taskInstallIso `
        -LogPath $taskIsoLog -IsoContainer $taskIsoContainer
    $taskNetwork = & "$PSScriptRoot\Initialize-IsuconNetwork.ps1" -SwitchName $InternalSwitchName -NetworkPrefix $NetworkPrefix
    for ($taskIndex = 0; $taskIndex -lt $taskMachines.Count; $taskIndex++) {
        $taskMachines[$taskIndex] | Add-Member -NotePropertyName IPAddress -NotePropertyValue $taskNetwork.VMAddresses[$taskIndex]
        Write-Host "$($taskMachines[$taskIndex].Name): $($taskMachines[$taskIndex].IPAddress)/$($taskNetwork.PrefixLength)"
    }
    foreach ($taskMachine in $taskMachines) {
        $taskJobs += Start-Job -Name $taskMachine.Name -ScriptBlock {
            param($Scripts, $Machine, $Iso, $Switch, $InternalSwitch, $PrefixLength, $Timeout, $Output, $IsoContainer)
            $ErrorActionPreference = 'Stop'
            Set-StrictMode -Version Latest
            Write-Host "VMを構築します: $($Machine.Name) ($($Machine.Role))"
            & "$Scripts\New-UbuntuVM.ps1" -Name $Machine.Name -IsoPath $Iso -AutoinstallIso -OutputPath $Output -SwitchName $Switch `
                -InternalSwitchName $InternalSwitch -IPAddress $Machine.IPAddress -PrefixLength $PrefixLength `
                -MemoryBytes $Machine.Memory -ProcessorCount 4 -TimeoutMinutes $Timeout -IsoContainer $IsoContainer | Out-Null
            & "$Scripts\Invoke-Isucon13Ansible.ps1" -VMName $Machine.Name -OutputPath $Output -Role $Machine.Role -ProcessorCount $Machine.CPUs
            Write-Host "ISUCON13の構築が完了しました: $($Machine.Name)"
        } -ArgumentList $PSScriptRoot, $taskMachine, $taskInstallIso, $SwitchName, $InternalSwitchName, $taskNetwork.PrefixLength, $TimeoutMinutes, $taskOutputRoot, $taskIsoContainer
    }
    $taskJobs | Receive-Job -Wait -ErrorAction Continue
    $taskFailed = @($taskJobs | Where-Object State -ne 'Completed')
    if ($taskFailed.Count) { throw "構築に失敗したVM: $($taskFailed.Name -join ', ')。VMとディスクを残しています。" }
} finally {
    try {
        $taskJobs | Where-Object State -in 'NotStarted','Running' | Stop-Job
        $taskJobs | Remove-Job
        if ((Test-Path -LiteralPath $taskInstallIso) -and
            -not @(Get-VM | Get-VMDvdDrive | Where-Object Path -eq $taskInstallIso).Count) {
            Remove-Item -LiteralPath $taskInstallIso
        }
    } finally {
        if ($taskIsoContainer) { Stop-IsoContainer -Container $taskIsoContainer }
    }
}
