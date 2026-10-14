#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$IsoPath,
    [Parameter(Mandatory)][string]$LogPath,
    [Parameter(Mandatory)][psobject]$IsoContainer
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandArgumentPassing = 'Standard'
$PSNativeCommandUseErrorActionPreference = $false
. "$PSScriptRoot\..\iso\IsoContainer.ps1"
$taskIso = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($IsoPath)
$taskLog = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogPath)
if (Test-Path -LiteralPath $taskIso) { throw "$taskIso は既に存在します。" }
Write-Host 'Ubuntu 26.04コンテナでインストール用ISOを準備しています。'
$taskLinuxIso = Get-IsoContainerPath -Container $IsoContainer -Path $taskIso
& wslc.exe exec $IsoContainer.Name sh /tool/ubuntu/prepare-autoinstall-iso.sh $taskLinuxIso `
    2>&1 | Tee-Object -FilePath $taskLog -Append | Out-Host
if ($LASTEXITCODE -ne 0) { throw "インストール用ISOの準備に失敗しました。ログ: $taskLog" }
