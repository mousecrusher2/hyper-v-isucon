#requires -Version 7.4
#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SwitchName,
    [Parameter(Mandatory)][string]$NetworkPrefix,
    [Parameter(Mandatory)][ValidateRange(1,65533)][int]$AddressCount
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$taskNetwork = [Net.IPNetwork]::Parse($NetworkPrefix)
$taskPrivate = @('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16') |
    ForEach-Object { [Net.IPNetwork]::Parse($_) } |
    Where-Object { $taskNetwork.PrefixLength -ge $_.PrefixLength -and $_.Contains($taskNetwork.BaseAddress) }
if (-not $taskPrivate) { throw 'プライベートIPv4のネットワークアドレスを指定してください。' }
$taskBytes = $taskNetwork.BaseAddress.GetAddressBytes()
[Array]::Reverse($taskBytes)
$taskBase = [BitConverter]::ToUInt32($taskBytes, 0)
$taskIPs = @(1..($AddressCount + 2) | ForEach-Object {
    $taskBytes = [BitConverter]::GetBytes([uint32]($taskBase + $_))
    [Array]::Reverse($taskBytes)
    [Net.IPAddress]::new($taskBytes)
})
if (-not $taskNetwork.Contains($taskIPs[-1])) { throw "NetworkPrefixにはVM $AddressCount 台とWindows側のIPを収容できるアドレス帯を指定してください。" }
$taskHostIP = $taskIPs[0].ToString()

$taskSwitch = New-VMSwitch -Name $SwitchName -SwitchType Internal -ErrorAction Stop
try {
    $taskDeadline = (Get-Date).AddSeconds(30)
    while ($true) {
        $taskAdapter = Get-NetAdapter -Name "vEthernet ($SwitchName)" -ErrorAction SilentlyContinue
        if ($taskAdapter) { break }
        if ((Get-Date) -ge $taskDeadline) {
            throw "仮想アダプター vEthernet ($SwitchName) の認識待ちがタイムアウトしました。"
        }
        Start-Sleep -Milliseconds 500
    }
    New-NetIPAddress -InterfaceIndex $taskAdapter.ifIndex -IPAddress $taskHostIP -PrefixLength $taskNetwork.PrefixLength -ErrorAction Stop | Out-Null
} catch {
    Remove-VMSwitch -VMSwitch $taskSwitch -Force -ErrorAction Stop
    throw
}
Write-Host "固定IP用ネットワーク: $SwitchName (Windows側 $taskHostIP/$($taskNetwork.PrefixLength))"
[pscustomobject]@{ HostIPAddress = $taskHostIP; VMAddresses = @($taskIPs[1..$AddressCount] | ForEach-Object { $_.ToString() }); PrefixLength = $taskNetwork.PrefixLength }
