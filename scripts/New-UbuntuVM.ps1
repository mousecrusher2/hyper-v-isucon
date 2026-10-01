#requires -Version 7.3
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$')][string]$Name,
    [Parameter(Mandatory)][string]$IsoPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [switch]$AutoinstallIso,
    [string]$SwitchName = 'Default Switch',
    [ValidateRange(2GB, [long]::MaxValue)][long]$MemoryMaximumBytes = 4GB,
    [int]$ProcessorCount = 4,
    [ValidateRange(5,120)][int]$TimeoutMinutes = 45
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandArgumentPassing = 'Standard'
$PSNativeCommandUseErrorActionPreference = $false
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskOutputRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
$taskIso = (Resolve-Path -LiteralPath $IsoPath).Path
$taskVmDir = Join-Path $taskOutputRoot "vm\$Name"
$taskDisk = Join-Path $taskVmDir 'disk.vhdx'
$taskKey = Join-Path $taskOutputRoot 'ssh\id_ed25519'
$taskKnownHosts = Join-Path $taskOutputRoot "ssh\known_hosts_$Name"
Get-VMSwitch -Name $SwitchName -ErrorAction Stop | Out-Null
if (Get-VM -Name $Name -ErrorAction SilentlyContinue) { throw "VM $Name は既に存在します。" }
if (Test-Path -LiteralPath $taskVmDir) { throw "$taskVmDir は既に存在します。" }
New-Item -ItemType Directory -Path "$taskVmDir\seed",(Split-Path -Parent $taskKey) -Force | Out-Null
if (-not (Test-Path -LiteralPath $taskKey)) {
    & ssh-keygen -q -t ed25519 -N '' -C 'hyper-isucon-local' -f $taskKey
    if ($LASTEXITCODE -ne 0) { throw 'SSH鍵の生成に失敗しました。' }
}
$taskPublicKey = (Get-Content -LiteralPath "$taskKey.pub" -Raw).Trim()
$taskUserData = (Get-Content -LiteralPath (Join-Path $taskRoot 'config\autoinstall.yaml') -Raw).
    Replace('{{hostname}}', $Name).Replace('{{ssh_public_key}}', ($taskPublicKey | ConvertTo-Json -Compress))
$taskEncoding = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText("$taskVmDir\seed\user-data", $taskUserData.Replace("`r`n", "`n") + "`n", $taskEncoding)
[IO.File]::WriteAllText("$taskVmDir\seed\meta-data", "instance-id: iid-$([guid]::NewGuid())`nlocal-hostname: $Name`n", $taskEncoding)
& "$PSScriptRoot\New-NoCloudIso.ps1" -SourcePath "$taskVmDir\seed" -IsoPath "$taskVmDir\seed.iso"
if (-not $AutoinstallIso) {
    $taskSourceIso = $taskIso
    $taskIso = Join-Path $taskVmDir 'install.iso'
    & "$PSScriptRoot\New-AutoinstallIso.ps1" -SourceIsoPath $taskSourceIso -IsoPath $taskIso `
        -LogPath (Join-Path $taskOutputRoot "logs\iso-$Name.log")
}

New-VHD -Path $taskDisk -Dynamic -SizeBytes 40GB -BlockSizeBytes 1MB -LogicalSectorSizeBytes 4096 -PhysicalSectorSizeBytes 4096 | Out-Null
$taskVM = New-VM -Name $Name -Generation 2 -MemoryStartupBytes 2GB -VHDPath $taskDisk -SwitchName $SwitchName -Path $taskVmDir
Set-VM -VM $taskVM -ProcessorCount $ProcessorCount -AutomaticCheckpointsEnabled $false -CheckpointType Disabled -AutomaticStartAction Nothing -AutomaticStopAction ShutDown
Disable-VMIntegrationService -VM $taskVM -Name VSS
Set-VMMemory -VM $taskVM -DynamicMemoryEnabled $true -MinimumBytes 2GB -StartupBytes 2GB -MaximumBytes $MemoryMaximumBytes
$taskDVD = Add-VMDvdDrive -VM $taskVM -Path $taskIso -Passthru
Add-VMDvdDrive -VM $taskVM -Path "$taskVmDir\seed.iso"
Set-VMFirmware -VM $taskVM -EnableSecureBoot Off -FirstBootDevice $taskDVD
Disable-VMConsoleSupport -VMName $Name
Start-VM -VM $taskVM

$taskDeadline = (Get-Date).AddMinutes($TimeoutMinutes)
Write-Host 'Ubuntu autoinstallの完了を待っています。'
while ((Get-VM -Name $Name).State -ne 'Off') {
    if ((Get-Date) -ge $taskDeadline) { throw 'autoinstallがタイムアウトしました。VMとディスクを残しています。' }
    Start-Sleep -Seconds 3
}
foreach ($taskDVD in Get-VMDvdDrive -VMName $Name) {
    Set-VMDvdDrive -VMName $Name -ControllerNumber $taskDVD.ControllerNumber -ControllerLocation $taskDVD.ControllerLocation -Path $null
}
if (-not $AutoinstallIso) { Remove-Item -LiteralPath $taskIso }
Set-VMFirmware -VMName $Name -FirstBootDevice (Get-VMHardDiskDrive -VMName $Name)
Start-VM -Name $Name
$taskVM = Get-VM -Name $Name
$taskOptions = @('-i', $taskKey, '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=5',
    '-o', 'StrictHostKeyChecking=accept-new', '-o', "HostKeyAlias=$Name",
    '-o', "UserKnownHostsFile=`"$taskKnownHosts`"")
$taskDeadline = (Get-Date).AddMinutes(10)
Write-Host 'UbuntuのIPv4とSSH接続を待っています。'
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
'@
& ssh @taskOptions "ubuntu@$taskIP" ($taskChecks.Replace("`r`n", "`n")) | ForEach-Object { Write-Host $_ }
if ($LASTEXITCODE -ne 0) { throw 'Ubuntuの初回起動確認に失敗しました。' }

[pscustomobject]@{
    Name = $Name
    VMId = $taskVM.Id
    VhdxPath = $taskDisk
    IPv4 = $taskIP
}
