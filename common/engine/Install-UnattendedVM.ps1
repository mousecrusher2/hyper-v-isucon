#requires -Version 7.4
#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$')][string]$Name,
    [Parameter(Mandatory)][string]$IsoPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$UserDataPath,
    [Parameter(Mandatory)][string]$SwitchName,
    [Parameter(Mandatory)][string]$InternalSwitchName,
    [Parameter(Mandatory)][string]$IPAddress,
    [Parameter(Mandatory)][ValidateRange(1,29)][int]$PrefixLength,
    [Parameter(Mandatory)][long]$MemoryBytes,
    [Parameter(Mandatory)][int]$ProcessorCount,
    [Parameter(Mandatory)][long]$DiskSizeBytes,
    [ValidateRange(0,[long]::MaxValue)][long]$MaximumIOPS = 0,
    [string]$InternalAdapterName = 'internal',
    [ValidateRange(5,120)][int]$TimeoutMinutes = 45,
    [Parameter(Mandatory)][psobject]$IsoContainer
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandArgumentPassing = 'Standard'
$PSNativeCommandUseErrorActionPreference = $false
$taskCommonRoot = Split-Path -Parent $PSScriptRoot
. "$taskCommonRoot\hyperv\HyperV-VM.ps1"
. "$taskCommonRoot\iso\IsoContainer.ps1"
$taskOutputRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
$taskIso = (Resolve-Path -LiteralPath $IsoPath).Path
$taskTemplate = Get-Content -LiteralPath $UserDataPath -Raw
$taskVmDir = Join-Path $taskOutputRoot "vm\$Name"
$taskPublicKey = (Get-Content -LiteralPath (Join-Path $taskOutputRoot 'ssh\id_ed25519.pub') -Raw).Trim()
$taskVM = New-UnattendedVM -Name $Name -Path $taskVmDir -SwitchName $SwitchName -InternalSwitchName $InternalSwitchName `
    -MemoryBytes $MemoryBytes -ProcessorCount $ProcessorCount -DiskSizeBytes $DiskSizeBytes `
    -MaximumIOPS $MaximumIOPS -InternalAdapterName $InternalAdapterName
$taskEncoding = [Text.UTF8Encoding]::new($false)
$taskUplinkMAC = (Get-VMNetworkAdapter -VM $taskVM -Name uplink).MacAddress.ToLowerInvariant() -replace '(..)(?!$)', '$1:'
$taskInternalMAC = (Get-VMNetworkAdapter -VM $taskVM -Name $InternalAdapterName).MacAddress.ToLowerInvariant() -replace '(..)(?!$)', '$1:'
$taskUserData = $taskTemplate.Replace('{{hostname}}', $Name).Replace('{{ssh_public_key}}', ($taskPublicKey | ConvertTo-Json -Compress)).
    Replace('{{uplink_mac}}', $taskUplinkMAC).Replace('{{internal_mac}}', $taskInternalMAC).
    Replace('{{ip_address}}', $IPAddress).Replace('{{prefix_length}}', [string]$PrefixLength)
$taskSeed = Join-Path $taskVmDir 'seed'
New-Item -ItemType Directory -Path $taskSeed | Out-Null
[IO.File]::WriteAllText((Join-Path $taskSeed 'user-data'), $taskUserData.Replace("`r`n", "`n") + "`n", $taskEncoding)
[IO.File]::WriteAllText((Join-Path $taskSeed 'meta-data'), "instance-id: iid-$Name`nlocal-hostname: $Name`n", $taskEncoding)
$taskLinuxSeed = Get-IsoContainerPath -Container $IsoContainer -Path $taskSeed
$taskLinuxSeedIso = Get-IsoContainerPath -Container $IsoContainer -Path "$taskVmDir\seed.iso"
& wslc.exe exec $IsoContainer.Name xorriso -no_rc -as mkisofs -V cidata -J -r -o $taskLinuxSeedIso $taskLinuxSeed `
    2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'NoCloud ISOの生成に失敗しました。' }
Mount-VMDvd -VM $taskVM -InstallerIsoPath $taskIso -SeedIsoPath "$taskVmDir\seed.iso"
Start-VM -VM $taskVM
Write-Host "OSインストール完了時の停止を待っています: $Name"
Wait-VMState -VMName $Name -State Off -TimeoutMinutes $TimeoutMinutes
Set-VMDiskBoot -VM $taskVM
# Hyper-V DVD removal must run in a different process from VM creation, while the VM is off.
& pwsh -NoProfile -Command "Get-VM -Id '$($taskVM.Id)' -ErrorAction Stop | Get-VMDvdDrive -ErrorAction Stop | Remove-VMDvdDrive -ErrorAction Stop"
if ($LASTEXITCODE -ne 0) { throw "VM $Name の仮想DVDドライブの削除に失敗しました (exit=$LASTEXITCODE)。" }
Start-VM -VM $taskVM
