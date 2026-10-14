#requires -Version 7.4
#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$VMName,
    [Parameter(Mandatory)][string]$IPAddress,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$ProvisionScriptPath,
    [Parameter(Mandatory)][string]$Role,
    [Parameter(Mandatory)][string]$ProvisionAssetsPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandArgumentPassing = 'Standard'
$PSNativeCommandUseErrorActionPreference = $false
$taskCommonRoot = Split-Path -Parent $PSScriptRoot
. "$taskCommonRoot\guest\Guest-SSH.ps1"
$taskOutputRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
$taskScript = (Resolve-Path -LiteralPath $ProvisionScriptPath).Path
$taskConnection = New-GuestSSHConnection -VMName $VMName -UserName 'ubuntu' -IPAddress $IPAddress `
    -IdentityFile (Join-Path $taskOutputRoot 'ssh\id_ed25519') -KnownHostsFile (Join-Path $taskOutputRoot "ssh\known_hosts_$VMName")
Wait-GuestSSH -Connection $taskConnection
$taskLog = Join-Path $taskOutputRoot "logs\provision-$VMName.log"
Send-GuestFile -Connection $taskConnection -SourcePath $ProvisionAssetsPath -DestinationPath '/home/ubuntu/' -LogPath $taskLog
Send-GuestFile -Connection $taskConnection -SourcePath $taskScript -DestinationPath '/home/ubuntu/provision.sh' -LogPath $taskLog
Invoke-GuestCommand -Connection $taskConnection -Command "bash /home/ubuntu/provision.sh $Role" -LogPath $taskLog
Write-Host "プロビジョニングが完了しました: $VMName (IPv4=$IPAddress)"
