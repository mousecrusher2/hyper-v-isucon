#requires -Version 7.4

function New-SSHKey {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $taskKey = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    New-Item -ItemType Directory -Path (Split-Path -Parent $taskKey) | Out-Null
    $PSNativeCommandUseErrorActionPreference = $false
    & ssh-keygen -q -t ed25519 -N '' -C 'hyper-isucon-local' -f $taskKey
    if ($LASTEXITCODE -ne 0) { throw 'SSH鍵の生成に失敗しました。' }
}

function New-GuestSSHConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$VMName,
        [Parameter(Mandatory)][string]$UserName,
        [Parameter(Mandatory)][string]$IdentityFile,
        [Parameter(Mandatory)][string]$KnownHostsFile,
        [Parameter(Mandatory)][string]$IPAddress
    )
    $taskKey = (Resolve-Path -LiteralPath $IdentityFile -ErrorAction Stop).Path
    $taskKnownHosts = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($KnownHostsFile)
    [pscustomobject]@{
        VMName = $VMName
        Target = "${UserName}@$IPAddress"
        Options = @('-i', $taskKey, '-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes', '-o', 'ConnectTimeout=5',
            '-o', 'StrictHostKeyChecking=accept-new', '-o', "HostKeyAlias=$VMName",
            '-o', "UserKnownHostsFile=`"$taskKnownHosts`"", '-o', 'GlobalKnownHostsFile=NUL')
    }
}

function Wait-GuestSSH {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Connection,
        [ValidateRange(1,120)][int]$TimeoutMinutes = 10
    )
    $PSNativeCommandUseErrorActionPreference = $false
    $taskOptions = $Connection.Options
    $taskDeadline = (Get-Date).AddMinutes($TimeoutMinutes)
    Write-Host "SSH接続を待っています: $($Connection.VMName)"
    do {
        & ssh @taskOptions $Connection.Target 'true' 2>$null
        if ($LASTEXITCODE -eq 0) { return }
        if ((Get-Date) -ge $taskDeadline) { throw "VM $($Connection.VMName) のSSH接続待ちがタイムアウトしました。" }
        Start-Sleep -Seconds 3
    } while ($true)
}

function Invoke-GuestCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Connection,
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string]$LogPath
    )
    $PSNativeCommandUseErrorActionPreference = $false
    $taskOptions = $Connection.Options
    & ssh @taskOptions $Connection.Target $Command 2>&1 |
        Tee-Object -FilePath $LogPath -Append | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "VM $($Connection.VMName) のコマンド実行に失敗しました (exit=$LASTEXITCODE)。ログ: $LogPath" }
}

function Send-GuestFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Connection,
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$DestinationPath,
        [Parameter(Mandatory)][string]$LogPath
    )
    $PSNativeCommandUseErrorActionPreference = $false
    $taskSource = (Resolve-Path -LiteralPath $SourcePath -ErrorAction Stop).Path
    $taskOptions = $Connection.Options
    & scp -r @taskOptions $taskSource "$($Connection.Target):$DestinationPath" 2>&1 |
        Tee-Object -FilePath $LogPath -Append | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "VM $($Connection.VMName) へのファイル転送に失敗しました (exit=$LASTEXITCODE)。ログ: $LogPath" }
}
