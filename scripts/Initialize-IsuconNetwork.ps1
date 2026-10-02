#requires -Version 7.3
#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$SwitchName = 'ISUCON13',
    [string]$NetworkPrefix = '192.168.13.0/24'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Get-IPv4Range([string]$Prefix) {
    if ($Prefix -notmatch '^(\d+\.\d+\.\d+\.\d+)/(\d|[12]\d|3[0-2])$') { throw "IPv4のCIDRを指定してください: $Prefix" }
    $taskAddress = [Net.IPAddress]::Parse($Matches[1])
    $taskLength = [int]$Matches[2]
    [long]$taskNumber = 0
    foreach ($taskByte in $taskAddress.GetAddressBytes()) { $taskNumber = $taskNumber * 256 + $taskByte }
    [long]$taskSize = [math]::Pow(2, 32 - $taskLength)
    $taskStart = $taskNumber - $taskNumber % $taskSize
    [pscustomobject]@{ Start = $taskStart; End = $taskStart + $taskSize - 1; Number = $taskNumber; PrefixLength = $taskLength }
}
function ConvertTo-IPv4([long]$Number) {
    @((($Number -shr 24) -band 255), (($Number -shr 16) -band 255), (($Number -shr 8) -band 255), ($Number -band 255)) -join '.'
}
$taskRange = Get-IPv4Range $NetworkPrefix
$taskAllowed = @('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16') |
    ForEach-Object { Get-IPv4Range $_ } | Where-Object { $taskRange.Start -ge $_.Start -and $taskRange.End -le $_.End }
if (-not $taskAllowed -or $taskRange.PrefixLength -gt 29 -or $taskRange.Number -ne $taskRange.Start) {
    throw 'NetworkPrefixにはVM4台とWindows側のIPを収容できる、プライベートIPv4のネットワークアドレス（/29以下）を指定してください。'
}
$taskHostIP = ConvertTo-IPv4 ($taskRange.Start + 1)
$taskHostPrefix = "$taskHostIP/$($taskRange.PrefixLength)"
$taskVMIPs = @(2..5 | ForEach-Object { ConvertTo-IPv4 ($taskRange.Start + $_) })
if (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue) {
    throw "スイッチ '$SwitchName' は既に存在します。InternalSwitchNameには新規作成するスイッチの名前を指定してください。"
}
$taskAddresses = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop)
$taskHint = '重複しないアドレス帯をNetworkPrefixで指定してください。'
foreach ($taskNat in Get-NetNat -ErrorAction Stop) {
    if (-not $taskNat.InternalIPInterfaceAddressPrefix) { continue }
    $taskExisting = Get-IPv4Range $taskNat.InternalIPInterfaceAddressPrefix
    if ($taskRange.Start -le $taskExisting.End -and $taskExisting.Start -le $taskRange.End) {
        throw "指定したアドレス帯 $NetworkPrefix が既存のネットワークと重複しています（$($taskNat.Name): $($taskNat.InternalIPInterfaceAddressPrefix)）。$taskHint"
    }
}
foreach ($taskAddress in $taskAddresses) {
    $taskExisting = Get-IPv4Range "$($taskAddress.IPAddress)/$($taskAddress.PrefixLength)"
    if ($taskRange.Start -le $taskExisting.End -and $taskExisting.Start -le $taskRange.End) {
        throw "指定したアドレス帯 $NetworkPrefix が既存のネットワークと重複しています（$($taskAddress.InterfaceAlias): $($taskAddress.IPAddress)/$($taskAddress.PrefixLength)）。$taskHint"
    }
}
foreach ($taskStore in 'ActiveStore','PersistentStore') {
    foreach ($taskRoute in Get-NetRoute -PolicyStore $taskStore -ErrorAction Stop |
        Where-Object { $_.DestinationPrefix -match '^\d+\.' -and $_.DestinationPrefix -ne '0.0.0.0/0' }) {
        $taskExisting = Get-IPv4Range $taskRoute.DestinationPrefix
        if ($taskRange.Start -le $taskExisting.End -and $taskExisting.Start -le $taskRange.End) {
            throw "指定したアドレス帯 $NetworkPrefix が既存のネットワークと重複しています（経路 $($taskRoute.DestinationPrefix)、$taskStore）。$taskHint"
        }
    }
}
$taskCreatedSwitch = $null
try {
    $taskCreatedSwitch = New-VMSwitch -Name $SwitchName -SwitchType Internal -ErrorAction Stop
    $taskAdapter = Get-NetAdapter -Name "vEthernet ($SwitchName)" -ErrorAction Stop
    New-NetIPAddress -InterfaceIndex $taskAdapter.ifIndex -IPAddress $taskHostIP -PrefixLength $taskRange.PrefixLength -ErrorAction Stop | Out-Null
    $taskDeadline = (Get-Date).AddMinutes(2)
    do {
        $taskReady = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.InterfaceIndex -eq $taskAdapter.ifIndex -and $_.IPAddress -eq $taskHostIP -and $_.AddressState -eq 'Preferred' })
        if ($taskReady.Count) { break }
        if ((Get-Date) -ge $taskDeadline) { throw "Windows側IPv4 $taskHostPrefix が利用可能になりませんでした。" }
        Start-Sleep -Seconds 2
    } while ($true)
    Write-Host "固定IP用ネットワーク: $SwitchName (Windows側 $taskHostPrefix)"
    [pscustomobject]@{ HostIPAddress = $taskHostIP; VMAddresses = @($taskVMIPs); PrefixLength = $taskRange.PrefixLength }
} catch {
    if ($taskCreatedSwitch) { Remove-VMSwitch -VMSwitch $taskCreatedSwitch -Force -ErrorAction Stop }
    throw
}
