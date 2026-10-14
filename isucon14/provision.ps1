#requires -Version 7.4
#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$')][string]$VMName,
    [Parameter(Mandatory)][string]$IPAddress,
    [Parameter(Mandatory)][string]$OutputPath,
    [ValidateSet('application', 'benchmarker')][string]$Role = 'application'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$taskCommonRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'common'
& "$taskCommonRoot\engine\Invoke-VMProvisioning.ps1" -VMName $VMName -IPAddress $IPAddress -OutputPath $OutputPath `
    -ProvisionScriptPath (Join-Path $PSScriptRoot 'provision.sh') -Role $Role -ProvisionAssetsPath (Join-Path $PSScriptRoot 'tls')
