#requires -Version 7.3
#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$')][string]$Name,
    [Parameter(Mandatory)][string]$IsoPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$UserDataPath,
    [Parameter(Mandatory)][string]$VerifyScriptPath,
    [Parameter(Mandatory)][string]$GuestUserName,
    [Parameter(Mandatory)][string]$SwitchName,
    [Parameter(Mandatory)][string]$InternalSwitchName,
    [Parameter(Mandatory)][string]$IPAddress,
    [Parameter(Mandatory)][ValidateRange(1,29)][int]$PrefixLength,
    [Parameter(Mandatory)][long]$MemoryBytes,
    [Parameter(Mandatory)][int]$ProcessorCount,
    [Parameter(Mandatory)][long]$DiskSizeBytes,
    [string]$InternalAdapterName = 'internal',
    [ValidateRange(5,120)][int]$TimeoutMinutes = 45,
    [string]$PrepareIsoScriptPath,
    [psobject]$IsoContainer
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandArgumentPassing = 'Standard'
$PSNativeCommandUseErrorActionPreference = $false
$taskCommonRoot = Split-Path -Parent $PSScriptRoot
. "$taskCommonRoot\hyperv\HyperV-VM.ps1"
. "$taskCommonRoot\guest\Guest-SSH.ps1"
. "$taskCommonRoot\iso\IsoContainer.ps1"
$taskOutputRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
$taskIso = (Resolve-Path -LiteralPath $IsoPath).Path
$taskTemplate = Get-Content -LiteralPath $UserDataPath -Raw
$taskVerify = Get-Content -LiteralPath $VerifyScriptPath -Raw
if ($PrepareIsoScriptPath) { $PrepareIsoScriptPath = (Resolve-Path -LiteralPath $PrepareIsoScriptPath).Path }
[Net.IPAddress]::Parse($IPAddress) | Out-Null
if (@(Get-VM | Get-VMNetworkAdapter | Where-Object { $_.SwitchName -eq $InternalSwitchName -and $_.IPAddresses -contains $IPAddress }).Count) {
    throw "固定IP $IPAddress は既にVMが使用しています。"
}
$taskVmDir = Join-Path $taskOutputRoot "vm\$Name"
$taskKey = Ensure-SSHKey -Path (Join-Path $taskOutputRoot 'ssh\id_ed25519')
$taskVM = New-UnattendedVM -Name $Name -Path $taskVmDir -SwitchName $SwitchName -InternalSwitchName $InternalSwitchName `
    -MemoryBytes $MemoryBytes -ProcessorCount $ProcessorCount -DiskSizeBytes $DiskSizeBytes -InternalAdapterName $InternalAdapterName
$taskEncoding = [Text.UTF8Encoding]::new($false)
$taskOwnContainer = $null
try {
    if (-not $IsoContainer) {
        $taskOwnContainer = Start-IsoContainer -OutputPath (Join-Path $taskOutputRoot 'vm') -SourceIsoPath $taskIso `
            -LogPath (Join-Path $taskOutputRoot "logs\iso-$Name.log")
        $IsoContainer = $taskOwnContainer
    }
    if ($PrepareIsoScriptPath) {
        $taskSourceIso = $taskIso
        $taskIso = Join-Path $taskVmDir 'install.iso'
        & $PrepareIsoScriptPath -SourceIsoPath $taskSourceIso -IsoPath $taskIso `
            -LogPath (Join-Path $taskOutputRoot "logs\iso-$Name.log") -IsoContainer $IsoContainer
    }
    $taskUplinkMAC = (Get-VMNetworkAdapter -VM $taskVM -Name uplink).MacAddress.ToLowerInvariant() -replace '(..)(?!$)', '$1:'
    $taskInternalMAC = (Get-VMNetworkAdapter -VM $taskVM -Name $InternalAdapterName).MacAddress.ToLowerInvariant() -replace '(..)(?!$)', '$1:'
    $taskUserData = $taskTemplate.Replace('{{hostname}}', $Name).Replace('{{ssh_public_key}}', ($taskKey.PublicKey | ConvertTo-Json -Compress)).
        Replace('{{uplink_mac}}', $taskUplinkMAC).Replace('{{internal_mac}}', $taskInternalMAC).
        Replace('{{ip_address}}', $IPAddress).Replace('{{prefix_length}}', [string]$PrefixLength)
    $taskSeed = Join-Path $taskVmDir 'seed'
    New-Item -ItemType Directory -Path $taskSeed | Out-Null
    [IO.File]::WriteAllText((Join-Path $taskSeed 'user-data'), $taskUserData.Replace("`r`n", "`n") + "`n", $taskEncoding)
    [IO.File]::WriteAllText((Join-Path $taskSeed 'meta-data'), "instance-id: iid-$([guid]::NewGuid())`nlocal-hostname: $Name`n", $taskEncoding)
    & "$taskCommonRoot\iso\New-NoCloudIso.ps1" -SourcePath $taskSeed -IsoPath "$taskVmDir\seed.iso" -IsoContainer $IsoContainer
} finally {
    if ($taskOwnContainer) { Stop-IsoContainer -Container $taskOwnContainer }
}
Mount-VMDvd -VM $taskVM -InstallerIsoPath $taskIso -SeedIsoPath "$taskVmDir\seed.iso"
Start-VM -VM $taskVM
Write-Host "OSインストール完了時の停止を待っています: $Name"
Wait-VMState -VMName $Name -State Off -TimeoutMinutes $TimeoutMinutes
Set-VMDiskBoot -VM $taskVM
Start-VM -VM $taskVM

$taskConnection = New-GuestSSHConnection -VMName $Name -UserName $GuestUserName -IdentityFile $taskKey.IdentityFile `
    -KnownHostsFile (Join-Path $taskOutputRoot "ssh\known_hosts_$Name") -IPAddress $IPAddress
$taskIP = Wait-GuestSSH -Connection $taskConnection -AdapterName $InternalAdapterName
$taskLog = Join-Path $taskOutputRoot "logs\install-$Name-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Invoke-GuestCommand -Connection $taskConnection -Command $taskVerify -LogPath $taskLog
[pscustomobject]@{
    Name = $Name
    VMId = $taskVM.Id
    VhdxPath = Join-Path $taskVmDir 'disk.vhdx'
    IPv4 = $taskIP
}
