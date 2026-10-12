#requires -Version 7.3
#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$')][string]$VMName,
    [Parameter(Mandatory)][string]$OutputPath,
    [ValidateSet('application', 'benchmarker')][string]$Role = 'application',
    [string]$IdentityFile,
    [ValidateRange(1,1024)][int]$ProcessorCount = $(if ($Role -eq 'benchmarker') { 8 } else { 2 })
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$taskCommonRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'common'
$taskBuildProfile = @{ ProcessorCount = 4; HwThreadCountPerCore = 0; MaximumIOPS = 0 }
$taskFinalProfile = @{
    ProcessorCount = $ProcessorCount
    HwThreadCountPerCore = 2
    MaximumIOPS = if ($Role -eq 'application') { [long](125MB / 8KB) } else { 0 }
}
& "$taskCommonRoot\engine\Invoke-VMProvisioning.ps1" -VMName $VMName -OutputPath $OutputPath `
    -ProvisionScriptPath (Join-Path $PSScriptRoot 'provision.sh') -GuestUserName 'ubuntu' -InternalAdapterName 'isucon' `
    -RemoteScriptPath '/home/ubuntu/provision-isucon13.sh' -ProvisionCommand "bash /home/ubuntu/provision-isucon13.sh $Role" `
    -IdentityFile $IdentityFile -BuildResourceProfile $taskBuildProfile -ResourceProfile $taskFinalProfile
