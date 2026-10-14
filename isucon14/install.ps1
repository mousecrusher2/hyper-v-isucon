#requires -Version 7.4
#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$')][string]$Name,
    [Parameter(Mandatory)][string]$IsoPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][psobject]$IsoContainer,
    [string]$SwitchName = 'Default Switch',
    [Parameter(Mandatory)][string]$InternalSwitchName,
    [Parameter(Mandatory)][ValidatePattern('^\d+\.\d+\.\d+\.\d+$')][string]$IPAddress,
    [Parameter(Mandatory)][ValidateRange(1,29)][int]$PrefixLength,
    [ValidateRange(2GB, [long]::MaxValue)][long]$MemoryBytes = 4GB,
    [ValidateRange(1,1024)][int]$ProcessorCount = 2,
    [ValidateRange(0,[long]::MaxValue)][long]$MaximumIOPS = [long](125MB / 8KB),
    [ValidateRange(5,120)][int]$TimeoutMinutes = 45
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$taskCommonRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'common'
$taskParameters = @{} + $PSBoundParameters
$taskParameters.SwitchName = $SwitchName
$taskParameters.MemoryBytes = $MemoryBytes
$taskParameters.ProcessorCount = $ProcessorCount
$taskParameters.MaximumIOPS = $MaximumIOPS
$taskParameters.DiskSizeBytes = 40GB
$taskParameters.InternalAdapterName = 'isucon'
$taskParameters.UserDataPath = Join-Path $PSScriptRoot 'autoinstall.yaml'
& "$taskCommonRoot\engine\Install-UnattendedVM.ps1" @taskParameters
