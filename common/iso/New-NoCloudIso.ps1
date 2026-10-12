#requires -Version 7.3
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourcePath,
    [Parameter(Mandatory)][string]$IsoPath,
    [Parameter(Mandatory)][psobject]$IsoContainer
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandArgumentPassing = 'Standard'
$PSNativeCommandUseErrorActionPreference = $false
. "$PSScriptRoot\IsoContainer.ps1"
$taskSource = (Resolve-Path -LiteralPath $SourcePath).Path
$taskOutput = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($IsoPath)
if (Test-Path -LiteralPath $taskOutput) { throw "$taskOutput は既に存在します。" }
$taskLinuxSource = Get-IsoContainerPath -Container $IsoContainer -Path $taskSource
$taskLinuxOutput = Get-IsoContainerPath -Container $IsoContainer -Path $taskOutput
& wslc.exe exec $IsoContainer.Name xorriso -no_rc -as mkisofs -V cidata -J -r -o $taskLinuxOutput $taskLinuxSource `
    2>&1 | ForEach-Object { Write-Host $_ }
if ($LASTEXITCODE -ne 0) {
    if (Test-Path -LiteralPath $taskOutput) { Remove-Item -LiteralPath $taskOutput }
    throw 'NoCloud ISOの生成に失敗しました。'
}
if (-not (Test-Path -LiteralPath $taskOutput -PathType Leaf)) { throw 'NoCloud ISOが生成されませんでした。' }
