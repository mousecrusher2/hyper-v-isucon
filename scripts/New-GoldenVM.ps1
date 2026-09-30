#requires -Version 7.3
[CmdletBinding()]
param(
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$')][string]$Name = 'ubuntu-golden',
    [string]$IsoPath = 'D:\iso\ubuntu-22.04.5-live-server-amd64.iso',
    [string]$SwitchName = 'Default Switch',
    [switch]$Start
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandArgumentPassing = 'Standard'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskIso = (Resolve-Path -LiteralPath $IsoPath).Path
$taskGoldenDir = Join-Path $taskRoot 'golden\ubuntu-server-22.04'
$taskDisk = Join-Path $taskGoldenDir 'disk.vhdx'
$taskKey = Join-Path $taskRoot '.local\ssh\id_ed25519'
$taskVMPath = Join-Path $taskRoot '.local\hyperv'
Get-VMSwitch -Name $SwitchName -ErrorAction Stop | Out-Null
if (Get-VM -Name $Name -ErrorAction SilentlyContinue) { throw "VM $Name は既に存在します。" }
if (Test-Path -LiteralPath $taskDisk) { throw "$taskDisk は既に存在します。" }
$taskOscdimg = Get-Command oscdimg -ErrorAction SilentlyContinue
$taskOscdimgPath = if ($taskOscdimg) { $taskOscdimg.Source } else {
    'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe'
}
if (-not (Test-Path -LiteralPath $taskOscdimgPath)) { throw 'Windows ADK Deployment Toolsのoscdimgが必要です。' }

New-Item -ItemType Directory -Path $taskGoldenDir,(Split-Path -Parent $taskKey),$taskVMPath -Force | Out-Null
if (-not (Test-Path -LiteralPath $taskKey)) {
    & ssh-keygen -q -t ed25519 -N '' -C 'hyper-isucon-local' -f $taskKey
    if ($LASTEXITCODE -ne 0) { throw 'SSH鍵の生成に失敗しました。' }
}
if (-not (Test-Path -LiteralPath "$taskKey.pub")) { throw 'SSH公開鍵が見つかりません。' }

$taskSeedDir = Join-Path $taskRoot '.local\golden-seed'
New-Item -ItemType Directory -Path $taskSeedDir -Force | Out-Null
$taskPublicKey = (Get-Content -LiteralPath "$taskKey.pub" -Raw).Trim() | ConvertTo-Json -Compress
$taskUserData = @"
#cloud-config
autoinstall:
  version: 1
  refresh-installer:
    update: false
  locale: en_US.UTF-8
  keyboard:
    layout: us
  storage:
    layout:
      name: direct
  identity:
    hostname: $Name
    username: ubuntu
    password: "!"
  ssh:
    install-server: true
    allow-pw: false
    authorized-keys:
      - $taskPublicKey
  packages:
    - linux-cloud-tools-virtual
  user-data:
    ssh_deletekeys: true
  late-commands:
    - 'echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /target/etc/sudoers.d/90-ubuntu'
    - chmod 0440 /target/etc/sudoers.d/90-ubuntu
    - curtin in-target --target=/target -- visudo -cf /etc/sudoers.d/90-ubuntu
  shutdown: poweroff
"@
$taskEncoding = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText((Join-Path $taskSeedDir 'user-data'), $taskUserData.Replace("`r`n", "`n") + "`n", $taskEncoding)
[IO.File]::WriteAllText((Join-Path $taskSeedDir 'meta-data'), "instance-id: iid-golden-$([guid]::NewGuid())`nlocal-hostname: $Name`n", $taskEncoding)
$taskSeedIso = Join-Path $taskRoot '.local\golden-seed.iso'
if (Test-Path -LiteralPath $taskSeedIso) { Remove-Item -LiteralPath $taskSeedIso -Force }
& $taskOscdimgPath -j2 -lcidata $taskSeedDir $taskSeedIso | ForEach-Object { Write-Host $_ }
if ($LASTEXITCODE -ne 0) { throw 'autoinstall用NoCloud CDの生成に失敗しました。' }

New-VHD -Path $taskDisk -Dynamic -SizeBytes 64GB -BlockSizeBytes 1MB | Out-Null
$taskVM = New-VM -Name $Name -Generation 2 -MemoryStartupBytes 4GB -VHDPath $taskDisk -SwitchName $SwitchName -Path $taskVMPath
Set-VM -VM $taskVM -ProcessorCount 2 -AutomaticCheckpointsEnabled $false -CheckpointType Disabled
Set-VMMemory -VM $taskVM -DynamicMemoryEnabled $false
$taskDVD = Add-VMDvdDrive -VM $taskVM -Path $taskIso -Passthru
Add-VMDvdDrive -VM $taskVM -Path $taskSeedIso
Set-VMFirmware -VM $taskVM -EnableSecureBoot Off -FirstBootDevice $taskDVD
if ($Start) {
    Start-VM -VM $taskVM
    Start-Sleep -Seconds 3
    $taskComputer = Get-CimInstance -Namespace root/virtualization/v2 -ClassName Msvm_ComputerSystem -Filter "Name='$($taskVM.Id)'"
    $taskKeyboard = Get-CimAssociatedInstance -InputObject $taskComputer -ResultClassName Msvm_Keyboard | Select-Object -First 1
    if (-not $taskKeyboard) { throw 'Hyper-Vの仮想キーボードを取得できませんでした。' }
    function Send-GuestKey([uint32]$Code) {
        $taskResult = Invoke-CimMethod -InputObject $taskKeyboard -MethodName TypeKey -Arguments @{ KeyCode = $Code }
        if ($taskResult.ReturnValue -ne 0) { throw '仮想キーボードの入力に失敗しました。' }
    }
    function Send-GuestText([string]$Text) {
        $taskResult = Invoke-CimMethod -InputObject $taskKeyboard -MethodName TypeText -Arguments @{ AsciiText = $Text }
        if ($taskResult.ReturnValue -ne 0) { throw '仮想キーボードの文字入力に失敗しました。' }
    }
    Send-GuestKey 27
    Start-Sleep -Seconds 1
    Send-GuestKey 27
    Start-Sleep -Seconds 1
    Send-GuestText 'c'
    Start-Sleep -Seconds 1
    foreach ($taskLine in @('linux /casper/vmlinuz autoinstall ---', 'initrd /casper/initrd', 'boot')) {
        Send-GuestText $taskLine
        Send-GuestKey 13
        Start-Sleep -Seconds 1
    }
}

[pscustomobject]@{
    VMName = $Name
    VhdxPath = $taskDisk
    IsoPath = $taskIso
    SshPublicKeyPath = "$taskKey.pub"
    SeedIsoPath = $taskSeedIso
}
