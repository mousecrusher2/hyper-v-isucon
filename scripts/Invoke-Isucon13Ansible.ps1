#requires -Version 7.3
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$')][string]$VMName,
    [string]$IdentityFile
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandArgumentPassing = 'Standard'
$taskRoot = Split-Path -Parent $PSScriptRoot
if (-not $IdentityFile) { $IdentityFile = Join-Path $taskRoot '.local\ssh\id_ed25519' }
$taskVM = Get-VM -Name $VMName
if ($taskVM.State -ne 'Running') { throw '起動中のVMを指定してください。' }
$taskDisk = @(Get-VMHardDiskDrive -VM $taskVM)
$taskVmRoot = Join-Path $taskRoot 'vm'
if ($taskDisk.Count -ne 1 -or -not [IO.Path]::GetFullPath($taskDisk[0].Path).StartsWith($taskVmRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'New-UbuntuVM.ps1で作成したVMを指定してください。'
}
$taskInfo = Get-VHD -Path $taskDisk[0].Path
if ($taskInfo.VhdFormat -ne 'VHDX' -or $taskInfo.ParentPath) { throw 'VMのディスクが独立したVHDXではありません。' }
$taskDeadline = (Get-Date).AddMinutes(5)
do {
    $taskIP = (Get-VMNetworkAdapter -VM $taskVM).IPAddresses |
        Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' -and $_ -notmatch '^169\.254\.' } | Select-Object -First 1
    if ($taskIP) { break }
    if ((Get-Date) -ge $taskDeadline) { throw 'VMのIPv4取得がタイムアウトしました。' }
    Start-Sleep -Seconds 3
} while ($true)

$taskOptions = @('-i', $IdentityFile, '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15',
    '-o', 'StrictHostKeyChecking=accept-new', '-o', "UserKnownHostsFile=$(Join-Path $taskRoot ".local\ssh\known_hosts_$VMName")")
$taskTarget = "ubuntu@$taskIP"
& scp @taskOptions (Join-Path $PSScriptRoot 'guest\provision-isucon13.sh') "${taskTarget}:/home/ubuntu/provision-isucon13.sh"
if ($LASTEXITCODE -ne 0) { throw 'provisionスクリプトの転送に失敗しました。' }
$taskLogDir = Join-Path $taskRoot '.local\logs'
New-Item -ItemType Directory -Path $taskLogDir -Force | Out-Null
$taskLog = Join-Path $taskLogDir "ansible-$VMName-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
& ssh @taskOptions $taskTarget 'bash /home/ubuntu/provision-isucon13.sh' 2>&1 | Tee-Object -FilePath $taskLog
if ($LASTEXITCODE -ne 0) { throw '公式ISUCON13 Ansibleの実行に失敗しました。' }
