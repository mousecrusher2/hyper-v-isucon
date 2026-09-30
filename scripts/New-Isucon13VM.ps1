#requires -Version 7.3
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$IsoPath,
    [ValidateCount(3,3)][ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$')][string[]]$ApplicationName = @('isucon13-app01', 'isucon13-app02', 'isucon13-app03'),
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$')][string]$BenchmarkerName = 'isucon13-bench',
    [string]$SwitchName = 'Default Switch',
    [long]$MemoryStartupBytes = 4GB,
    [ValidateRange(1,1024)][int]$ProcessorCount = 2,
    [long]$BenchmarkerMemoryStartupBytes = 8GB,
    [ValidateRange(1,1024)][int]$BenchmarkerProcessorCount = 8,
    [ValidateRange(5,120)][int]$TimeoutMinutes = 45
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskMachines = @(
    foreach ($taskVMName in $ApplicationName) {
        [pscustomobject]@{ Name = $taskVMName; Role = 'application'; Memory = $MemoryStartupBytes; CPUs = $ProcessorCount }
    }
    [pscustomobject]@{ Name = $BenchmarkerName; Role = 'benchmarker'; Memory = $BenchmarkerMemoryStartupBytes; CPUs = $BenchmarkerProcessorCount }
)
if ($taskMachines.Count -ne @($taskMachines.Name | Sort-Object -Unique).Count) { throw 'VM名が重複しています。' }
foreach ($taskVMName in $taskMachines.Name) {
    if (Get-VM -Name $taskVMName -ErrorAction SilentlyContinue) { throw "VM $taskVMName は既に存在します。" }
    $taskVmDir = Join-Path $taskRoot "vm\$taskVMName"
    if (Test-Path -LiteralPath $taskVmDir) { throw "$taskVmDir は既に存在します。" }
}
$taskIso = (Resolve-Path -LiteralPath $IsoPath).Path
Get-VMSwitch -Name $SwitchName -ErrorAction Stop | Out-Null
# Prepare the shared key before starting workers.
$taskKey = Join-Path $taskRoot '.local\ssh\id_ed25519'
New-Item -ItemType Directory -Path (Split-Path -Parent $taskKey) -Force | Out-Null
if (-not (Test-Path -LiteralPath $taskKey)) {
    & ssh-keygen -q -t ed25519 -N '' -C 'hyper-isucon-local' -f $taskKey
    if ($LASTEXITCODE -ne 0) { throw 'SSH鍵の生成に失敗しました。' }
}

$taskJobs = @()
try {
    foreach ($taskMachine in $taskMachines) {
        $taskJobs += Start-Job -Name $taskMachine.Name -ScriptBlock {
            param($Scripts, $Machine, $Iso, $Switch, $Timeout)
            $ErrorActionPreference = 'Stop'
            Set-StrictMode -Version Latest
            Write-Host "VMを構築します: $($Machine.Name) ($($Machine.Role))"
            & "$Scripts\New-UbuntuVM.ps1" -Name $Machine.Name -IsoPath $Iso -SwitchName $Switch `
                -MemoryStartupBytes $Machine.Memory -ProcessorCount 4 -TimeoutMinutes $Timeout | Out-Null
            & "$Scripts\Invoke-Isucon13Ansible.ps1" -VMName $Machine.Name -Role $Machine.Role -ProcessorCount $Machine.CPUs
            Write-Host "ISUCON13の構築が完了しました: $($Machine.Name)"
        } -ArgumentList $PSScriptRoot, $taskMachine, $taskIso, $SwitchName, $TimeoutMinutes
    }
    $taskJobs | Receive-Job -Wait -ErrorAction Continue
    $taskFailed = @($taskJobs | Where-Object State -ne 'Completed')
    if ($taskFailed.Count) { throw "構築に失敗したVM: $($taskFailed.Name -join ', ')。VMとディスクを残しています。" }
} finally {
    $taskJobs | Where-Object State -in 'NotStarted','Running' | Stop-Job
    $taskJobs | Remove-Job
}
