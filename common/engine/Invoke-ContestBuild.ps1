#requires -Version 7.4
#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$IsoPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][psobject[]]$Machines,
    [Parameter(Mandatory)][string]$InstallScriptPath,
    [Parameter(Mandatory)][string]$ProvisionScriptPath,
    [Parameter(Mandatory)][string]$SwitchName,
    [Parameter(Mandatory)][string]$InternalSwitchName,
    [Parameter(Mandatory)][string]$NetworkPrefix,
    [ValidateRange(5,120)][int]$TimeoutMinutes = 45
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandArgumentPassing = 'Standard'
$PSNativeCommandUseErrorActionPreference = $false
$taskCommonRoot = Split-Path -Parent $PSScriptRoot
. "$taskCommonRoot\iso\IsoContainer.ps1"
. "$taskCommonRoot\guest\Guest-SSH.ps1"
$taskOutputRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
$taskIso = (Resolve-Path -LiteralPath $IsoPath).Path
$taskInstallScript = (Resolve-Path -LiteralPath $InstallScriptPath).Path
$taskProvisionScript = (Resolve-Path -LiteralPath $ProvisionScriptPath).Path
if (-not $Machines.Count -or $Machines.Count -ne @($Machines.Name | Sort-Object -Unique).Count) { throw 'VM名が空または重複しています。' }
foreach ($taskVMName in $Machines.Name) {
    if (Get-VM -Name $taskVMName -ErrorAction SilentlyContinue) { throw "VM $taskVMName は既に存在します。" }
    $taskVmDir = Join-Path $taskOutputRoot "vm\$taskVMName"
    if (Test-Path -LiteralPath $taskVmDir) { throw "$taskVmDir は既に存在します。" }
}
Get-VMSwitch -Name $SwitchName -ErrorAction Stop | Out-Null
if ($SwitchName -eq $InternalSwitchName) { throw 'インターネット用と固定IP用には別のスイッチを指定してください。' }
# Generate the shared key before workers start.
New-SSHKey -Path (Join-Path $taskOutputRoot 'ssh\id_ed25519')
$taskNetwork = & "$taskCommonRoot\hyperv\Initialize-Network.ps1" -SwitchName $InternalSwitchName -NetworkPrefix $NetworkPrefix -AddressCount $Machines.Count
$taskIsoLog = Join-Path $taskOutputRoot 'logs\iso.log'
$taskIsoContainer = Start-IsoContainer -OutputPath (Join-Path $taskOutputRoot 'vm') -SourceIsoPath $taskIso -LogPath $taskIsoLog
$taskInstallIso = Join-Path $taskOutputRoot 'vm\install.iso'
$taskJobs = @()
try {
    & "$taskCommonRoot\ubuntu\New-AutoinstallIso.ps1" -IsoPath $taskInstallIso -LogPath $taskIsoLog -IsoContainer $taskIsoContainer
    for ($taskIndex = 0; $taskIndex -lt $Machines.Count; $taskIndex++) {
        $taskMachine = $Machines[$taskIndex]
        $taskIP = $taskNetwork.VMAddresses[$taskIndex]
        Write-Host "$($taskMachine.Name): $taskIP/$($taskNetwork.PrefixLength)"
        $taskJobs += Start-Job -Name $taskMachine.Name -ScriptBlock {
            param($InstallScript, $ProvisionScript, $Machine, $Iso, $Switch, $InternalSwitch, $IP, $PrefixLength, $Timeout, $Output, $IsoContainer)
            $ErrorActionPreference = 'Stop'
            Set-StrictMode -Version Latest
            $taskInstallParameters = $Machine.InstallParameters
            $taskProvisionParameters = $Machine.ProvisionParameters
            Write-Host "VMを構築します: $($Machine.Name)"
            & $InstallScript -Name $Machine.Name -IsoPath $Iso -OutputPath $Output -SwitchName $Switch `
                -InternalSwitchName $InternalSwitch -IPAddress $IP -PrefixLength $PrefixLength `
                -TimeoutMinutes $Timeout -IsoContainer $IsoContainer @taskInstallParameters
            & $ProvisionScript -VMName $Machine.Name -IPAddress $IP -OutputPath $Output @taskProvisionParameters
            Write-Host "構築が完了しました: $($Machine.Name)"
        } -ArgumentList $taskInstallScript, $taskProvisionScript, $taskMachine, $taskInstallIso, $SwitchName, $InternalSwitchName, $taskIP, $taskNetwork.PrefixLength, $TimeoutMinutes, $taskOutputRoot, $taskIsoContainer
    }
    $taskJobs | Receive-Job -Wait -ErrorAction Continue
    $taskFailed = @($taskJobs | Where-Object State -ne 'Completed')
    if ($taskFailed.Count) { throw "構築に失敗したVM: $($taskFailed.Name -join ', ')。VMとディスクを残しています。" }
} finally {
    $taskJobs | Where-Object State -in 'NotStarted','Running' | Stop-Job
    $taskJobs | Remove-Job
    Stop-IsoContainer -Container $taskIsoContainer
}
Remove-Item -LiteralPath $taskInstallIso
