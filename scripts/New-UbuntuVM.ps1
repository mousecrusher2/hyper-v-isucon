#requires -Version 7.3
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$')][string]$Name,
    [Parameter(Mandatory)][string]$GoldenVhdxPath,
    [string]$SwitchName = 'Default Switch',
    [string]$SshPublicKeyPath,
    [long]$MemoryStartupBytes = 4GB,
    [int]$ProcessorCount = 2,
    [switch]$Start
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$taskRoot = Split-Path -Parent $PSScriptRoot
if (-not $SshPublicKeyPath) { $SshPublicKeyPath = Join-Path $taskRoot '.local\ssh\id_ed25519.pub' }
$taskGolden = (Resolve-Path -LiteralPath $GoldenVhdxPath).Path
$taskDiskInfo = Get-VHD -Path $taskGolden
if ($taskDiskInfo.VhdFormat -ne 'VHDX' -or $taskDiskInfo.ParentPath -or $taskDiskInfo.Attached) {
    throw '停止済みで親ディスクを持たないgolden VHDXを指定してください。'
}
Get-VMSwitch -Name $SwitchName -ErrorAction Stop | Out-Null
if (Get-VM -Name $Name -ErrorAction SilentlyContinue) { throw "VM $Name は既に存在します。" }
$taskVmDir = Join-Path $taskRoot "vm\$Name"
if (Test-Path -LiteralPath $taskVmDir) { throw "$taskVmDir は既に存在します。" }
$taskPublicKey = (Get-Content -LiteralPath $SshPublicKeyPath -Raw).Trim()
if ($taskPublicKey -notmatch '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-\S+) [A-Za-z0-9+/=]+( .*)?$') {
    throw 'SSH公開鍵の形式が不正です。'
}
$taskOscdimg = Get-Command oscdimg -ErrorAction SilentlyContinue
if ($taskOscdimg) { $taskOscdimgPath = $taskOscdimg.Source }
else {
    $taskOscdimgPath = 'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe'
    if (-not (Test-Path -LiteralPath $taskOscdimgPath)) { throw 'Windows ADK Deployment Toolsのoscdimgが必要です。' }
}

New-Item -ItemType Directory -Path "$taskVmDir\seed" -Force | Out-Null
$taskEncoding = [Text.UTF8Encoding]::new($false)
$taskInstanceId = 'iid-' + [guid]::NewGuid().ToString()
$taskMetadata = "instance-id: $taskInstanceId`nlocal-hostname: $Name`n"
$taskUserData = @"
#cloud-config
hostname: $Name
manage_etc_hosts: true
users:
  - default
ssh_authorized_keys:
  - $($taskPublicKey | ConvertTo-Json -Compress)
ssh_deletekeys: true
ssh_pwauth: false
"@
[IO.File]::WriteAllText("$taskVmDir\seed\meta-data", $taskMetadata, $taskEncoding)
[IO.File]::WriteAllText("$taskVmDir\seed\user-data", $taskUserData.Replace("`r`n", "`n") + "`n", $taskEncoding)
& $taskOscdimgPath -j2 -lcidata "$taskVmDir\seed" "$taskVmDir\seed.iso" | ForEach-Object { Write-Host $_ }
if ($LASTEXITCODE -ne 0) { throw 'VM用NoCloud CDの生成に失敗しました。' }

# Full file copy, never New-VHD -ParentPath or an imported VM configuration.
$taskDisk = Join-Path $taskVmDir 'disk.vhdx'
Copy-Item -LiteralPath $taskGolden -Destination $taskDisk
$taskVM = New-VM -Name $Name -Generation 2 -MemoryStartupBytes $MemoryStartupBytes -VHDPath $taskDisk -SwitchName $SwitchName -Path $taskVmDir
Set-VM -VM $taskVM -ProcessorCount $ProcessorCount -AutomaticCheckpointsEnabled $false -CheckpointType Disabled
Set-VMMemory -VM $taskVM -DynamicMemoryEnabled $false
Set-VMFirmware -VM $taskVM -EnableSecureBoot Off -FirstBootDevice (Get-VMHardDiskDrive -VM $taskVM)
Add-VMDvdDrive -VM $taskVM -Path "$taskVmDir\seed.iso"
if ($Start) { Start-VM -VM $taskVM }

[pscustomobject]@{
    Name = $Name
    VMId = $taskVM.Id
    VhdxPath = $taskDisk
    InstanceId = $taskInstanceId
    State = (Get-VM -Name $Name).State
}
