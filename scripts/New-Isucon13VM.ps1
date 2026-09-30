#requires -Version 7.3
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$IsoPath,
    [ValidateCount(3,3)][ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$')][string[]]$ApplicationName = @('isucon13-app01', 'isucon13-app02', 'isucon13-app03'),
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$')][string]$BenchmarkerName = 'isucon13-bench',
    [string]$SwitchName = 'Default Switch',
    [long]$MemoryStartupBytes = 4GB,
    [int]$ProcessorCount = 2,
    [long]$BenchmarkerMemoryStartupBytes = 8GB,
    [int]$BenchmarkerProcessorCount = 8,
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
$taskInstallParameters = @{ IsoPath = $IsoPath; SwitchName = $SwitchName; TimeoutMinutes = $TimeoutMinutes }
foreach ($taskMachine in $taskMachines) {
    Write-Host "VMを構築します: $($taskMachine.Name) ($($taskMachine.Role))"
    $taskInstallParameters['Name'] = $taskMachine.Name
    $taskInstallParameters['MemoryStartupBytes'] = $taskMachine.Memory
    $taskInstallParameters['ProcessorCount'] = $taskMachine.CPUs
    & "$PSScriptRoot\New-UbuntuVM.ps1" @taskInstallParameters | Out-Null
    & "$PSScriptRoot\Invoke-Isucon13Ansible.ps1" -VMName $taskMachine.Name -Role $taskMachine.Role
    Write-Host "ISUCON13の構築が完了しました: $($taskMachine.Name)"
}
