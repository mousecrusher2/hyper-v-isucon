#requires -Version 7.3
[CmdletBinding()]
param(
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$')][string]$VMName = 'ubuntu-golden',
    [Parameter(Mandatory)][System.Net.IPAddress]$Address,
    [string]$IdentityFile
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandArgumentPassing = 'Standard'
$PSNativeCommandUseErrorActionPreference = $false
$taskRoot = Split-Path -Parent $PSScriptRoot
if (-not $IdentityFile) { $IdentityFile = Join-Path $taskRoot '.local\ssh\id_ed25519' }
$taskVM = Get-VM -Name $VMName
$taskDisks = @(Get-VMHardDiskDrive -VM $taskVM)
$taskExpectedDisk = [IO.Path]::GetFullPath((Join-Path $taskRoot 'golden\ubuntu-server-22.04\disk.vhdx'))
if ($taskVM.State -ne 'Running' -or $taskDisks.Count -ne 1 -or [IO.Path]::GetFullPath($taskDisks[0].Path) -ne $taskExpectedDisk) {
    throw '起動中のgolden作成用VMを指定してください。'
}
$taskIPs = (Get-VMNetworkAdapter -VM $taskVM).IPAddresses
if ($Address.ToString() -notin $taskIPs) { throw 'Addressが指定VMのIP通知と一致しません。' }
$taskOptions = @('-i', $IdentityFile, '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15',
    '-o', 'StrictHostKeyChecking=accept-new', '-o', "UserKnownHostsFile=$(Join-Path $taskRoot ".local\ssh\known_hosts_$VMName")")
$taskTarget = "ubuntu@$Address"
& scp @taskOptions (Join-Path $PSScriptRoot 'guest\generalize-ubuntu.sh') "${taskTarget}:/home/ubuntu/generalize-ubuntu.sh"
if ($LASTEXITCODE -ne 0) { throw 'generalizeスクリプトの転送に失敗しました。' }
# The completion marker and powered-off VM confirm success even if SSH is disconnected.
$taskOutput = & ssh @taskOptions $taskTarget 'sudo -n bash /home/ubuntu/generalize-ubuntu.sh' 2>&1
$taskExit = $LASTEXITCODE
$taskOutput | ForEach-Object { Write-Host $_ }
if (($taskOutput | Out-String) -notmatch '(?m)^GENERALIZE_COMPLETE\s*$') {
    throw "generalizeの完了を確認できませんでした (SSH exit=$taskExit)。VMを確認してください。"
}
$taskDeadline = (Get-Date).AddMinutes(2)
while ((Get-VM -Name $VMName).State -ne 'Off') {
    if ((Get-Date) -ge $taskDeadline) { throw 'VMのshutdown待ちがタイムアウトしました。' }
    Start-Sleep -Seconds 2
}
$taskInfo = Get-VHD -Path $taskExpectedDisk
if ($taskInfo.VhdFormat -ne 'VHDX' -or $taskInfo.ParentPath -or $taskInfo.Attached) {
    throw '停止済みの独立VHDXではありません。'
}
# Remove only the build VM registration; preserve its full VHDX as the golden.
Remove-VM -Name $VMName -Force
[pscustomobject]@{ GoldenVhdxPath = $taskExpectedDisk; State = 'Generalized and shut down' }
