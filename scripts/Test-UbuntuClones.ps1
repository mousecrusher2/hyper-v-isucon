#requires -Version 7.3
[CmdletBinding()]
param(
    [string[]]$VMName = @('ubuntu-clone01', 'ubuntu-clone02'),
    [string]$IdentityFile,
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandArgumentPassing = 'Standard'
if ($VMName.Count -lt 2 -or @($VMName | Select-Object -Unique).Count -ne $VMName.Count) {
    throw '異なるVM名を2台以上指定してください。'
}
$taskRoot = Split-Path -Parent $PSScriptRoot
if (-not $IdentityFile) { $IdentityFile = Join-Path $taskRoot '.local\ssh\id_ed25519' }
$taskGuestCommand = @'
set -eu
sudo -n true
sudo -n cloud-init status --wait --long >&2
systemctl is-active --quiet ssh
test -d /sys/firmware/efi
test ! -e /etc/cloud/cloud.cfg.d/99-installer.cfg
python3 - <<'PY'
import json, pathlib, subprocess
print(json.dumps({
    "hostname": subprocess.check_output(["hostname"], text=True).strip(),
    "machine_id": pathlib.Path("/etc/machine-id").read_text().strip(),
    "ssh_host_fingerprint": subprocess.check_output([
        "ssh-keygen", "-lf", "/etc/ssh/ssh_host_ed25519_key.pub"
    ], text=True).split()[1],
    "instance_id": pathlib.Path("/var/lib/cloud/data/instance-id").read_text().strip(),
}))
PY
'@

$taskResults = foreach ($taskName in $VMName) {
    $taskVM = Get-VM -Name $taskName
    if ($taskVM.Generation -ne 2 -or $taskVM.State -ne 'Running') { throw "$taskName は起動中のGeneration 2 VMではありません。" }
    $taskDisk = Get-VMHardDiskDrive -VM $taskVM
    $taskDiskInfo = Get-VHD -Path $taskDisk.Path
    if ($taskDiskInfo.ParentPath -or $taskDiskInfo.VhdFormat -ne 'VHDX') { throw "$taskName のディスクが独立したVHDXではありません。" }
    $taskIPv4 = $null
    for ($taskAttempt = 0; $taskAttempt -lt 120; $taskAttempt++) {
        $taskAdapter = Get-VMNetworkAdapter -VM $taskVM
        $taskIPv4 = $taskAdapter.IPAddresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' -and $_ -notmatch '^169\.254\.' } | Select-Object -First 1
        if ($taskIPv4) { break }
        Start-Sleep -Seconds 3
    }
    if (-not $taskIPv4) { throw "$taskName のIPv4を取得できませんでした。" }
    $taskKnownHosts = Join-Path $taskRoot ".local\ssh\known_hosts_$taskName"
    $taskFactsJSON = & ssh -i $IdentityFile -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$taskKnownHosts" "ubuntu@$taskIPv4" $taskGuestCommand
    if ($LASTEXITCODE -ne 0) { throw "$taskName のSSH検証に失敗しました。" }
    $taskFacts = $taskFactsJSON | ConvertFrom-Json
    $taskMetadataFile = Join-Path $taskRoot "vm\$taskName\seed\meta-data"
    $taskExpectedId = ((Get-Content -LiteralPath $taskMetadataFile | Where-Object { $_ -match '^instance-id: ' }) -replace '^instance-id: ', '').Trim()
    if ($taskFacts.hostname -ne $taskName -or $taskFacts.instance_id -ne $taskExpectedId) {
        throw "$taskName がそのVMのNoCloud設定を適用していません。"
    }
    [pscustomobject]@{
        VMName = $taskName
        VMId = $taskVM.Id.ToString()
        MAC = $taskAdapter.MacAddress
        IPv4 = $taskIPv4
        MachineId = $taskFacts.machine_id
        SshHostFingerprint = $taskFacts.ssh_host_fingerprint
        InstanceId = $taskFacts.instance_id
        ParentPath = $taskDiskInfo.ParentPath
    }
}

foreach ($taskField in @('VMId', 'MAC', 'MachineId', 'SshHostFingerprint', 'InstanceId')) {
    if (@($taskResults.$taskField | Select-Object -Unique).Count -ne $VMName.Count) {
        throw "$taskField がVM間で重複しています。"
    }
}
$taskReport = if ($ReportPath) { [IO.Path]::GetFullPath($ReportPath) } else { Join-Path $taskRoot '.local\results\clone-verification.json' }
New-Item -ItemType Directory -Path (Split-Path -Parent $taskReport) -Force | Out-Null
$taskResults | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $taskReport -Encoding utf8
$taskResults | Format-List
Write-Output "Clone verification passed: $taskReport"
