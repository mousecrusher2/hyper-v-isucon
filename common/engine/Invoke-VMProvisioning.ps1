#requires -Version 7.4
#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$VMName,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$ProvisionScriptPath,
    [Parameter(Mandatory)][string]$RemoteScriptPath,
    [Parameter(Mandatory)][string]$ProvisionCommand,
    [Parameter(Mandatory)][string]$GuestUserName,
    [string]$ProvisionAssetsPath,
    [string]$InternalAdapterName = 'internal',
    [string]$IdentityFile
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandArgumentPassing = 'Standard'
$PSNativeCommandUseErrorActionPreference = $false
$taskCommonRoot = Split-Path -Parent $PSScriptRoot
. "$taskCommonRoot\guest\Guest-SSH.ps1"
$taskOutputRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
$taskScript = (Resolve-Path -LiteralPath $ProvisionScriptPath).Path
if (-not $IdentityFile) { $IdentityFile = Join-Path $taskOutputRoot 'ssh\id_ed25519' }
$taskVM = Get-VM -Name $VMName -ErrorAction Stop
if ($taskVM.State -ne 'Running') { throw '起動中のVMを指定してください。' }
$taskDisk = @(Get-VMHardDiskDrive -VM $taskVM)
$taskVmRoot = Join-Path $taskOutputRoot 'vm'
if ($taskDisk.Count -ne 1 -or -not [IO.Path]::GetFullPath($taskDisk[0].Path).StartsWith($taskVmRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw '指定した保存先にある、install.ps1で作成したVMを指定してください。'
}
$taskInfo = Get-VHD -Path $taskDisk[0].Path
if ($taskInfo.VhdFormat -ne 'VHDX' -or $taskInfo.ParentPath) { throw 'VMのディスクが独立したVHDXではありません。' }
$taskConnection = New-GuestSSHConnection -VMName $VMName -UserName $GuestUserName -IdentityFile $IdentityFile `
    -KnownHostsFile (Join-Path $taskOutputRoot "ssh\known_hosts_$VMName")
$taskIP = Wait-GuestSSH -Connection $taskConnection -AdapterName $InternalAdapterName -TimeoutMinutes 5
$taskLog = Join-Path $taskOutputRoot "logs\provision-$VMName-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
if ($ProvisionAssetsPath) {
    Send-GuestFile -Connection $taskConnection -SourcePath $ProvisionAssetsPath -DestinationPath "/home/$GuestUserName/" -LogPath $taskLog
}
Send-GuestFile -Connection $taskConnection -SourcePath $taskScript -DestinationPath $RemoteScriptPath -LogPath $taskLog
Invoke-GuestCommand -Connection $taskConnection -Command $ProvisionCommand -LogPath $taskLog
Write-Host "プロビジョニングが完了しました: $VMName (IPv4=$taskIP)"
