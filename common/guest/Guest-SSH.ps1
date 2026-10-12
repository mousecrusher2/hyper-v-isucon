#requires -Version 7.3

function Ensure-SSHKey {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $taskKey = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    New-Item -ItemType Directory -Path (Split-Path -Parent $taskKey) -Force | Out-Null
    if (-not (Test-Path -LiteralPath $taskKey -PathType Leaf)) {
        $PSNativeCommandUseErrorActionPreference = $false
        & ssh-keygen -q -t ed25519 -N '' -C 'hyper-isucon-local' -f $taskKey
        if ($LASTEXITCODE -ne 0) { throw 'SSH鍵の生成に失敗しました。' }
    }
    if (-not (Test-Path -LiteralPath "$taskKey.pub" -PathType Leaf)) { throw "SSH公開鍵がありません: $taskKey.pub" }
    [pscustomobject]@{ IdentityFile = $taskKey; PublicKey = (Get-Content -LiteralPath "$taskKey.pub" -Raw).Trim() }
}

function New-GuestSSHConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$VMName,
        [Parameter(Mandatory)][string]$UserName,
        [Parameter(Mandatory)][string]$IdentityFile,
        [Parameter(Mandatory)][string]$KnownHostsFile,
        [string]$IPAddress
    )
    $taskKey = (Resolve-Path -LiteralPath $IdentityFile -ErrorAction Stop).Path
    $taskKnownHosts = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($KnownHostsFile)
    New-Item -ItemType Directory -Path (Split-Path -Parent $taskKnownHosts) -Force | Out-Null
    [pscustomobject]@{
        VMName = $VMName
        UserName = $UserName
        IPAddress = $IPAddress
        Target = if ($IPAddress) { "${UserName}@$IPAddress" } else { '' }
        Options = @('-i', $taskKey, '-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes', '-o', 'ConnectTimeout=5',
            '-o', 'StrictHostKeyChecking=accept-new', '-o', "HostKeyAlias=$VMName",
            '-o', "UserKnownHostsFile=`"$taskKnownHosts`"", '-o', 'GlobalKnownHostsFile=NUL')
    }
}

function Wait-GuestSSH {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Connection,
        [string]$AdapterName = 'internal',
        [ValidateRange(1,120)][int]$TimeoutMinutes = 10
    )
    $PSNativeCommandUseErrorActionPreference = $false
    $taskOptions = $Connection.Options
    $taskDeadline = (Get-Date).AddMinutes($TimeoutMinutes)
    Write-Host "SSH接続を待っています: $($Connection.VMName)"
    do {
        $taskIP = $Connection.IPAddress
        if (-not $taskIP) {
            $taskIP = (Get-VMNetworkAdapter -VMName $Connection.VMName -Name $AdapterName -ErrorAction Stop).IPAddresses |
                Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
        }
        if ($taskIP) {
            $Connection.Target = "$($Connection.UserName)@$taskIP"
            & ssh @taskOptions $Connection.Target 'true' 2>$null
            if ($LASTEXITCODE -eq 0) { return $taskIP }
        }
        if ((Get-Date) -ge $taskDeadline) { throw "VM $($Connection.VMName) のSSH接続待ちがタイムアウトしました。" }
        Start-Sleep -Seconds 3
    } while ($true)
}

function Invoke-GuestCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Connection,
        [Parameter(Mandatory)][string]$Command,
        [string]$LogPath
    )
    if (-not $Connection.Target) { throw '先にWait-GuestSSHで接続先を確認してください。' }
    $PSNativeCommandUseErrorActionPreference = $false
    $taskOptions = $Connection.Options
    if ($LogPath) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $LogPath) -Force | Out-Null
        & ssh @taskOptions $Connection.Target ($Command.Replace("`r`n", "`n")) 2>&1 |
            Tee-Object -FilePath $LogPath -Append | ForEach-Object { Write-Host $_ }
    } else {
        & ssh @taskOptions $Connection.Target ($Command.Replace("`r`n", "`n")) 2>&1 | ForEach-Object { Write-Host $_ }
    }
    if ($LASTEXITCODE -ne 0) { throw "VM $($Connection.VMName) のコマンド実行に失敗しました (exit=$LASTEXITCODE)。ログ: $LogPath" }
}

function Send-GuestFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Connection,
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath,
        [string]$LogPath
    )
    if (-not $Connection.Target) { throw '先にWait-GuestSSHで接続先を確認してください。' }
    $PSNativeCommandUseErrorActionPreference = $false
    $taskSource = (Resolve-Path -LiteralPath $SourcePath -ErrorAction Stop).Path
    $taskOptions = $Connection.Options
    if ($LogPath) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $LogPath) -Force | Out-Null
        & scp @taskOptions $taskSource "$($Connection.Target):$DestinationPath" 2>&1 |
            Tee-Object -FilePath $LogPath -Append | ForEach-Object { Write-Host $_ }
    } else {
        & scp @taskOptions $taskSource "$($Connection.Target):$DestinationPath" 2>&1 | ForEach-Object { Write-Host $_ }
    }
    if ($LASTEXITCODE -ne 0) { throw "VM $($Connection.VMName) へのファイル転送に失敗しました (exit=$LASTEXITCODE)。ログ: $LogPath" }
}
