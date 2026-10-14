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
    [string]$PrepareIsoScriptPath,
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
if ($PrepareIsoScriptPath) { $PrepareIsoScriptPath = (Resolve-Path -LiteralPath $PrepareIsoScriptPath).Path }
if (-not $Machines.Count -or $Machines.Count -ne @($Machines.Name | Sort-Object -Unique).Count) { throw 'VM名が空または重複しています。' }
foreach ($taskVMName in $Machines.Name) {
    if (Get-VM -Name $taskVMName -ErrorAction SilentlyContinue) { throw "VM $taskVMName は既に存在します。" }
    $taskVmDir = Join-Path $taskOutputRoot "vm\$taskVMName"
    if (Test-Path -LiteralPath $taskVmDir) { throw "$taskVmDir は既に存在します。" }
}
Get-VMSwitch -Name $SwitchName -ErrorAction Stop | Out-Null
if ($SwitchName -eq $InternalSwitchName) { throw 'インターネット用と固定IP用には別のスイッチを指定してください。' }
# Generate the shared key before workers start.
Ensure-SSHKey -Path (Join-Path $taskOutputRoot 'ssh\id_ed25519') | Out-Null
$taskJobs = @()
$taskIsoContainer = $null
$taskInstallIso = $taskIso
try {
    # Validate and configure the network before starting expensive ISO preparation.
    $taskNetwork = & "$taskCommonRoot\hyperv\Initialize-Network.ps1" -SwitchName $InternalSwitchName -NetworkPrefix $NetworkPrefix -AddressCount $Machines.Count
    try {
        $taskIsoLog = Join-Path $taskOutputRoot "logs\iso-$([guid]::NewGuid()).log"
        $taskIsoContainer = Start-IsoContainer -OutputPath (Join-Path $taskOutputRoot 'vm') -SourceIsoPath $taskIso -LogPath $taskIsoLog
        if ($PrepareIsoScriptPath) {
            $taskInstallIso = Join-Path $taskOutputRoot "vm\install-$([guid]::NewGuid()).iso"
            & $PrepareIsoScriptPath -SourceIsoPath $taskIso -IsoPath $taskInstallIso -LogPath $taskIsoLog -IsoContainer $taskIsoContainer
        }
    } catch {
        # No VM workers have started, so the newly created switch is safe to remove.
        Get-VMSwitch -Name $InternalSwitchName -ErrorAction Stop | Remove-VMSwitch -Force -ErrorAction Stop
        throw
    }
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
            & $InstallScript -Name $Machine.Name -IsoPath $Iso -PreparedIso -OutputPath $Output -SwitchName $Switch `
                -InternalSwitchName $InternalSwitch -IPAddress $IP -PrefixLength $PrefixLength `
                -TimeoutMinutes $Timeout -IsoContainer $IsoContainer @taskInstallParameters | Out-Null
            & $ProvisionScript -VMName $Machine.Name -OutputPath $Output @taskProvisionParameters
            Write-Host "構築が完了しました: $($Machine.Name)"
        } -ArgumentList $taskInstallScript, $taskProvisionScript, $taskMachine, $taskInstallIso, $SwitchName, $InternalSwitchName, $taskIP, $taskNetwork.PrefixLength, $TimeoutMinutes, $taskOutputRoot, $taskIsoContainer
    }
    $taskJobs | Receive-Job -Wait -ErrorAction Continue
    $taskFailed = @($taskJobs | Where-Object State -ne 'Completed')
    if ($taskFailed.Count) { throw "構築に失敗したVM: $($taskFailed.Name -join ', ')。VMとディスクを残しています。" }
} finally {
    try {
        $taskJobs | Where-Object State -in 'NotStarted','Running' | Stop-Job
        $taskJobs | Remove-Job
    } finally {
        try {
            if ($taskIsoContainer) { Stop-IsoContainer -Container $taskIsoContainer }
        } finally {
            if ($taskInstallIso -ne $taskIso -and (Test-Path -LiteralPath $taskInstallIso)) {
                try {
                    $taskMountedDVDs = @(Get-VM -ErrorAction Stop | Get-VMDvdDrive -ErrorAction Stop |
                        Where-Object Path -eq $taskInstallIso)
                    if ($taskMountedDVDs.Count) {
                        Write-Warning "構築用ISOはVMが使用しているため残しています: $taskInstallIso"
                    } else {
                        Remove-Item -LiteralPath $taskInstallIso -ErrorAction Stop
                    }
                } catch {
                }
            }
        }
    }
}
