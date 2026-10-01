#requires -Version 7.3
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceIsoPath,
    [Parameter(Mandatory)][string]$IsoPath,
    [Parameter(Mandatory)][string]$LogPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandArgumentPassing = 'Standard'
$PSNativeCommandUseErrorActionPreference = $false
$taskSource = (Resolve-Path -LiteralPath $SourceIsoPath).Path
$taskIso = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($IsoPath)
$taskLog = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogPath)
if (Test-Path -LiteralPath $taskIso) { throw "$taskIso は既に存在します。" }
Get-Command wslc.exe -ErrorAction Stop | Out-Null
$taskDirectory = Split-Path -Parent $taskIso
New-Item -ItemType Directory -Path $taskDirectory,(Split-Path -Parent $taskLog) -Force | Out-Null
$taskScript = Join-Path $PSScriptRoot 'prepare-autoinstall-iso.sh'
Write-Host 'Ubuntu 26.04コンテナでインストール用ISOを準備しています。'
& wslc.exe run --rm --env DEBIAN_FRONTEND=noninteractive `
    --volume "${taskSource}:/input/source.iso:ro" `
    --volume "${taskDirectory}:/output" `
    --volume "${taskScript}:/tool/prepare-autoinstall-iso.sh:ro" `
    ubuntu:26.04 sh /tool/prepare-autoinstall-iso.sh "/output/$([IO.Path]::GetFileName($taskIso))" `
    2>&1 | Tee-Object -FilePath $taskLog | ForEach-Object { Write-Host $_ }
if ($LASTEXITCODE -ne 0) {
    if (Test-Path -LiteralPath $taskIso) { Remove-Item -LiteralPath $taskIso }
    throw "インストール用ISOの準備に失敗しました。ログ: $taskLog"
}
if (-not (Test-Path -LiteralPath $taskIso -PathType Leaf)) { throw 'インストール用ISOが生成されませんでした。' }
