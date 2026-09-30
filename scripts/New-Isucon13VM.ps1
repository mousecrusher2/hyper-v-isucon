#requires -Version 7.3
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$')][string]$Name,
    [Parameter(Mandatory)][string]$IsoPath,
    [string]$SwitchName = 'Default Switch',
    [long]$MemoryStartupBytes = 4GB,
    [int]$ProcessorCount = 2,
    [ValidateRange(5,120)][int]$TimeoutMinutes = 45
)

$ErrorActionPreference = 'Stop'
& "$PSScriptRoot\New-UbuntuVM.ps1" @PSBoundParameters | Out-Null
& "$PSScriptRoot\Invoke-Isucon13Ansible.ps1" -VMName $Name
Write-Host "ISUCON13の構築が完了しました: $Name"
