#requires -Version 7.3

function Start-IsoContainer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)][string]$LogPath,
        [string]$SourceIsoPath
    )
    Get-Command wslc.exe -ErrorAction Stop | Out-Null
    $taskDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
    $taskLog = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogPath)
    New-Item -ItemType Directory -Path $taskDirectory,(Split-Path -Parent $taskLog) -Force | Out-Null
    $taskContainer = [pscustomobject]@{ Name = "hyper-isucon-iso-$([guid]::NewGuid())"; OutputPath = $taskDirectory }
    $taskArguments = @('run', '--detach', '--name', $taskContainer.Name, '--env', 'DEBIAN_FRONTEND=noninteractive',
        '--volume', "${taskDirectory}:/output", '--volume', "${PSScriptRoot}:/tool:ro")
    if ($SourceIsoPath) {
        $taskSource = (Resolve-Path -LiteralPath $SourceIsoPath -ErrorAction Stop).Path
        $taskArguments += @('--volume', "${taskSource}:/input/source.iso:ro")
    }
    $taskInitialized = $false
    try {
        & wslc.exe @taskArguments ubuntu:26.04 sleep infinity | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'ISO生成用コンテナの起動に失敗しました。' }
        $taskInstall = @'
set -eu
apt-get update
apt-get upgrade -y
apt-get install -y --no-install-recommends xorriso
'@
        & wslc.exe exec $taskContainer.Name sh -c ($taskInstall.Replace("`r`n", "`n")) `
            2>&1 | Tee-Object -FilePath $taskLog | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { throw "ISO生成用ツールの準備に失敗しました。ログ: $taskLog" }
        $taskInitialized = $true
        $taskContainer
    } finally {
        if (-not $taskInitialized) {
            $taskExisting = & wslc.exe list --all --filter "name=^$($taskContainer.Name)$" --quiet
            if ($LASTEXITCODE -ne 0) { throw "ISO生成用コンテナの存在確認に失敗しました: $($taskContainer.Name)" }
            if ($taskExisting) { Stop-IsoContainer -Container $taskContainer }
        }
    }
}

function Stop-IsoContainer {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Container)
    & wslc.exe remove --force $Container.Name | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "ISO生成用コンテナの削除に失敗しました: $($Container.Name)" }
}

function Get-IsoContainerPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Container, [Parameter(Mandatory)][string]$Path)
    $taskPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $taskRelative = [IO.Path]::GetRelativePath($Container.OutputPath, $taskPath).Replace('\', '/')
    if ([IO.Path]::IsPathRooted($taskRelative) -or $taskRelative -eq '..' -or $taskRelative.StartsWith('../')) {
        throw "ISO生成用コンテナの出力フォルダー内のパスを指定してください: $taskPath"
    }
    "/output/$taskRelative"
}
