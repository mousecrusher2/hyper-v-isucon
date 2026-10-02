#requires -Version 7.3
#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$')][string]$VMName,
    [Parameter(Mandatory)][string]$OutputPath,
    [ValidateSet('application', 'benchmarker')][string]$Role = 'application',
    [string]$IdentityFile,
    [ValidateRange(1,1024)][int]$ProcessorCount = $(if ($Role -eq 'benchmarker') { 8 } else { 2 })
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandArgumentPassing = 'Standard'
$taskOutputRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
if (-not $IdentityFile) { $IdentityFile = Join-Path $taskOutputRoot 'ssh\id_ed25519' }
$taskKnownHosts = Join-Path $taskOutputRoot "ssh\known_hosts_$VMName"
$taskVM = Get-VM -Name $VMName
if ($taskVM.State -ne 'Running') { throw '起動中のVMを指定してください。' }
$taskDisk = @(Get-VMHardDiskDrive -VM $taskVM)
$taskVmRoot = Join-Path $taskOutputRoot 'vm'
if ($taskDisk.Count -ne 1 -or -not [IO.Path]::GetFullPath($taskDisk[0].Path).StartsWith($taskVmRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw '指定した保存先にある、New-UbuntuVM.ps1で作成したVMを指定してください。'
}
$taskInfo = Get-VHD -Path $taskDisk[0].Path
if ($taskInfo.VhdFormat -ne 'VHDX' -or $taskInfo.ParentPath) { throw 'VMのディスクが独立したVHDXではありません。' }
$taskOptions = @('-i', $IdentityFile, '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15',
    '-o', 'StrictHostKeyChecking=accept-new', '-o', "HostKeyAlias=$VMName",
    '-o', "UserKnownHostsFile=`"$taskKnownHosts`"")
function Wait-GuestSSH {
    $taskDeadline = (Get-Date).AddMinutes(5)
    do {
        $taskIP = (Get-VMNetworkAdapter -VM $taskVM -Name isucon -ErrorAction Stop).IPAddresses |
            Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
        if ($taskIP) {
            & ssh @taskOptions "ubuntu@$taskIP" 'true' 2>$null
            if ($LASTEXITCODE -eq 0) { return $taskIP }
        }
        if ((Get-Date) -ge $taskDeadline) { throw 'VMのSSH接続待ちがタイムアウトしました。' }
        Start-Sleep -Seconds 3
    } while ($true)
}

$taskDisk | Set-VMHardDiskDrive -MaximumIOPS 0
if ($taskVM.ProcessorCount -ne 4 -or (Get-VMMemory -VM $taskVM).Minimum -ne 2GB) {
    Stop-VM -VM $taskVM
    Set-VM -VM $taskVM -ProcessorCount 4
    Set-VMMemory -VM $taskVM -MinimumBytes 2GB
    Start-VM -VM $taskVM
}
$taskIP = Wait-GuestSSH
$taskTarget = "ubuntu@$taskIP"
& scp @taskOptions (Join-Path $PSScriptRoot 'guest\provision-isucon13.sh') "${taskTarget}:/home/ubuntu/provision-isucon13.sh"
if ($LASTEXITCODE -ne 0) { throw 'provisionスクリプトの転送に失敗しました。' }
$taskLogDir = Join-Path $taskOutputRoot 'logs'
New-Item -ItemType Directory -Path $taskLogDir -Force | Out-Null
$taskLog = Join-Path $taskLogDir "ansible-$VMName-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
& ssh @taskOptions $taskTarget "bash /home/ubuntu/provision-isucon13.sh $Role" 2>&1 | Tee-Object -FilePath $taskLog
if ($LASTEXITCODE -ne 0) { throw '公式ISUCON13 Ansibleの実行に失敗しました。' }

Stop-VM -VM $taskVM
Set-VM -VM $taskVM -ProcessorCount $ProcessorCount
Set-VMMemory -VM $taskVM -MinimumBytes 512MB
$taskMaximumIOPS = if ($Role -eq 'application') { 32000 } else { 0 }
Get-VMHardDiskDrive -VM $taskVM | Set-VMHardDiskDrive -MaximumIOPS $taskMaximumIOPS
Start-VM -VM $taskVM
$taskFinalIP = Wait-GuestSSH
Write-Host "構築後の設定を適用しました: $VMName ($ProcessorCount vCPU, MaximumIOPS=$taskMaximumIOPS, IPv4=$taskFinalIP)"
