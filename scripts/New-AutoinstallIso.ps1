#requires -Version 7.3
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceIsoPath,
    [Parameter(Mandatory)][string]$IsoPath,
    [Parameter(Mandatory)][string]$LogPath,
    [psobject]$IsoContainer
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandArgumentPassing = 'Standard'
$PSNativeCommandUseErrorActionPreference = $false
. "$PSScriptRoot\IsoContainer.ps1"
$taskSource = (Resolve-Path -LiteralPath $SourceIsoPath).Path
$taskIso = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($IsoPath)
$taskLog = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogPath)
if (Test-Path -LiteralPath $taskIso) { throw "$taskIso は既に存在します。" }
Get-Command wslc.exe -ErrorAction Stop | Out-Null
$taskDirectory = Split-Path -Parent $taskIso
New-Item -ItemType Directory -Path $taskDirectory,(Split-Path -Parent $taskLog) -Force | Out-Null
Write-Host 'Ubuntu 26.04コンテナでインストール用ISOを準備しています。'
$taskOwnContainer = $null
try {
    if (-not $IsoContainer) {
        $taskOwnContainer = Start-IsoContainer -OutputPath $taskDirectory -SourceIsoPath $taskSource -LogPath $taskLog
        $IsoContainer = $taskOwnContainer
    }
    $taskLinuxIso = Get-IsoContainerPath -Container $IsoContainer -Path $taskIso
    & wslc.exe exec $IsoContainer.Name sh /tool/prepare-autoinstall-iso.sh $taskLinuxIso `
        2>&1 | Tee-Object -FilePath $taskLog -Append | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        if (Test-Path -LiteralPath $taskIso) { Remove-Item -LiteralPath $taskIso }
        throw "インストール用ISOの準備に失敗しました。ログ: $taskLog"
    }
    if (-not (Test-Path -LiteralPath $taskIso -PathType Leaf)) { throw 'インストール用ISOが生成されませんでした。' }
} finally {
    if ($taskOwnContainer) { Stop-IsoContainer -Container $taskOwnContainer }
}
