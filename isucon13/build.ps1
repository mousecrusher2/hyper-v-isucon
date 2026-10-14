#requires -Version 7.4
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
    [ValidateRange(2GB, [long]::MaxValue)][long]$MemoryBytes = 4GB,
    [ValidateRange(1,1024)][int]$ProcessorCount = 2,
    [ValidateRange(2GB, [long]::MaxValue)][long]$BenchmarkerMemoryBytes = 4GB,
    [ValidateRange(1,1024)][int]$BenchmarkerProcessorCount = 8,
    [ValidateRange(5,120)][int]$TimeoutMinutes = 45
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$taskCommonRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'common'
$taskMachines = @(
    foreach ($taskVMName in $ApplicationName) {
        [pscustomobject]@{
            Name = $taskVMName
            InstallParameters = @{ MemoryBytes = $MemoryBytes; ProcessorCount = $ProcessorCount }
            ProvisionParameters = @{ Role = 'application' }
        }
    }
    [pscustomobject]@{
        Name = $BenchmarkerName
        InstallParameters = @{ MemoryBytes = $BenchmarkerMemoryBytes; ProcessorCount = $BenchmarkerProcessorCount; MaximumIOPS = 0 }
        ProvisionParameters = @{ Role = 'benchmarker' }
    }
)
& "$taskCommonRoot\engine\Invoke-ContestBuild.ps1" -IsoPath $IsoPath -OutputPath $OutputPath -Machines $taskMachines `
    -InstallScriptPath (Join-Path $PSScriptRoot 'install.ps1') -ProvisionScriptPath (Join-Path $PSScriptRoot 'provision.ps1') `
    -SwitchName $SwitchName -InternalSwitchName $InternalSwitchName -NetworkPrefix $NetworkPrefix -TimeoutMinutes $TimeoutMinutes
