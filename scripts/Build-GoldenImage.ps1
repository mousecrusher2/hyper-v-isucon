#requires -Version 7.3
[CmdletBinding()]
param(
    [string]$IsoPath = 'D:\iso\ubuntu-22.04.5-live-server-amd64.iso',
    [string]$SwitchName = 'Default Switch',
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$')][string]$VMName = 'ubuntu-golden',
    [ValidateRange(5,120)][int]$TimeoutMinutes = 45
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandArgumentPassing = 'Standard'
$PSNativeCommandUseErrorActionPreference = $false
$taskRoot = Split-Path -Parent $PSScriptRoot
& "$PSScriptRoot\New-GoldenVM.ps1" -Name $VMName -IsoPath $IsoPath -SwitchName $SwitchName -Start | Out-Null
# Installer poweroff avoids booting the installation ISO again on reboot.
$taskDeadline = (Get-Date).AddMinutes($TimeoutMinutes)
Write-Host 'Ubuntu autoinstallの完了とpoweroffを待っています。'
while ((Get-VM -Name $VMName).State -ne 'Off') {
    if ((Get-Date) -ge $taskDeadline) { throw 'autoinstallがタイムアウトしました。VMとディスクを残しています。' }
    Start-Sleep -Seconds 3
}
$taskVM = Get-VM -Name $VMName
foreach ($taskDVD in Get-VMDvdDrive -VMName $VMName) {
    Set-VMDvdDrive -VMName $VMName -ControllerNumber $taskDVD.ControllerNumber -ControllerLocation $taskDVD.ControllerLocation -Path $null
}
Set-VMFirmware -VMName $VMName -FirstBootDevice (Get-VMHardDiskDrive -VMName $VMName)
Start-VM -Name $VMName
$taskVM = Get-VM -Name $VMName

$taskKey = Join-Path $taskRoot '.local\ssh\id_ed25519'
$taskOptions = @('-i', $taskKey, '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=5',
    '-o', 'StrictHostKeyChecking=accept-new', '-o', "UserKnownHostsFile=$(Join-Path $taskRoot ".local\ssh\known_hosts_$VMName")")
$taskDeadline = (Get-Date).AddMinutes(10)
Write-Host 'インストール済みUbuntuのIPv4とSSH接続を待っています。'
do {
    $taskIP = (Get-VMNetworkAdapter -VM $taskVM).IPAddresses |
        Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' -and $_ -notmatch '^169\.254\.' } | Select-Object -First 1
    if ($taskIP) {
        & ssh @taskOptions "ubuntu@$taskIP" 'true' 2>$null
        if ($LASTEXITCODE -eq 0) { break }
    }
    if ((Get-Date) -ge $taskDeadline) { throw 'UbuntuのSSH接続待ちがタイムアウトしました。' }
    Start-Sleep -Seconds 3
} while ($true)
$taskChecks = @'
set -eu
sudo -n true
sudo -n cloud-init status --wait --long
. /etc/os-release
test "$ID" = ubuntu && test "$VERSION_ID" = 22.04
test -d /sys/firmware/efi
systemctl is-active --quiet ssh
sudo -n python3 - <<'PY'
from cloudinit.stages import Init
init = Init()
init.read_cfg()
assert init.cfg.get("ssh_deletekeys", True)
print("ssh_deletekeys: true")
PY
'@
& ssh @taskOptions "ubuntu@$taskIP" $taskChecks
if ($LASTEXITCODE -ne 0) { throw 'Ubuntuの初回起動確認に失敗しました。' }
& "$PSScriptRoot\Complete-GoldenImage.ps1" -VMName $VMName -Address $taskIP -IdentityFile $taskKey
