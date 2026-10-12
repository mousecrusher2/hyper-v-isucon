#requires -Version 7.3
#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$IsoPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [ValidateCount(3,3)][ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$')][string[]]$ApplicationName = @('isucon14-app01', 'isucon14-app02', 'isucon14-app03'),
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$')][string]$BenchmarkerName = 'isucon14-bench',
    [string]$SwitchName = 'Default Switch',
    [string]$InternalSwitchName = 'ISUCON14',
    [string]$NetworkPrefix = '192.168.14.0/24',
    [Alias('MemoryMaximumBytes')][ValidateRange(2GB, [long]::MaxValue)][long]$MemoryBytes = 4GB,
    [ValidateRange(1,1024)][int]$ProcessorCount = 2,
    [Alias('BenchmarkerMemoryMaximumBytes')][ValidateRange(2GB, [long]::MaxValue)][long]$BenchmarkerMemoryBytes = 4GB,
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
            InstallParameters = @{ MemoryBytes = $MemoryBytes; ProcessorCount = 4 }
            ProvisionParameters = @{ Role = 'application'; ProcessorCount = $ProcessorCount }
        }
    }
    [pscustomobject]@{
        Name = $BenchmarkerName
        InstallParameters = @{ MemoryBytes = $BenchmarkerMemoryBytes; ProcessorCount = 4 }
        ProvisionParameters = @{ Role = 'benchmarker'; ProcessorCount = $BenchmarkerProcessorCount }
    }
)
& "$taskCommonRoot\engine\Invoke-ContestBuild.ps1" -IsoPath $IsoPath -OutputPath $OutputPath -Machines $taskMachines `
    -InstallScriptPath (Join-Path $PSScriptRoot 'install.ps1') -ProvisionScriptPath (Join-Path $PSScriptRoot 'provision.ps1') `
    -PrepareIsoScriptPath "$taskCommonRoot\ubuntu\New-AutoinstallIso.ps1" -SwitchName $SwitchName `
    -InternalSwitchName $InternalSwitchName -NetworkPrefix $NetworkPrefix -TimeoutMinutes $TimeoutMinutes
