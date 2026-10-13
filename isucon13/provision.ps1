#requires -Version 7.4
#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$')][string]$VMName,
    [Parameter(Mandatory)][string]$OutputPath,
    [ValidateSet('application', 'benchmarker')][string]$Role = 'application',
    [string]$IdentityFile
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$taskCommonRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'common'
$taskAssets = if ($Role -eq 'application') { Join-Path $PSScriptRoot 'tls' }
& "$taskCommonRoot\engine\Invoke-VMProvisioning.ps1" -VMName $VMName -OutputPath $OutputPath `
    -ProvisionScriptPath (Join-Path $PSScriptRoot 'provision.sh') -GuestUserName 'ubuntu' -InternalAdapterName 'isucon' `
    -RemoteScriptPath '/home/ubuntu/provision-isucon13.sh' -ProvisionCommand "bash /home/ubuntu/provision-isucon13.sh $Role" `
    -IdentityFile $IdentityFile -ProvisionAssetsPath $taskAssets
