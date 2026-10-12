# 共通手順

## 前提条件

- Windows 10 / 11（Hyper-V を有効化済み）
- PowerShell 7.3 以上（構築スクリプトは管理者権限で実行）
- Windows OpenSSH Client（`ssh`、`scp`、`ssh-keygen`）
- WSLC を利用できる WSL 2.9.3 以上（`wslc version` で確認）
- 対象大会に対応する Ubuntu Server の公式 amd64 ISO：[22.04](https://releases.ubuntu.com/22.04/) / [24.04](https://releases.ubuntu.com/24.04/)
- VM 4 台に割り当てるメモリ、仮想ディスクを保存する空き容量、インターネット接続

## VM の共通仕様

| 項目 | アプリ用 VM | ベンチマーク用 VM |
| :--- | :--- | :--- |
| 台数 | 3 台 | 1 台 |
| vCPU | 各 2 | 8 |
| メモリ | 各固定 4 GiB | 固定 4 GiB |
| ディスク | 各 40 GiB の独立した VHDX | 40 GiB の独立した VHDX |
| 最大 IOPS | 16,000 | 制限なし |
| swap | 無効 | 無効 |
| ログイン | `ubuntu`（SSH 公開鍵認証、sudo パスワード不要） | 同左 |

構築中は全 VM を 4 vCPU・IOPS 制限なしで起動し、ゲストのプロビジョニング成功後に停止して CPU・IOPS の設定を適用し、再起動します。メモリは構築時から固定です。
ベンチ VM の本番メモリは 8 GiB ですが、ここでは 4 GiB を既定値としています。`-BenchmarkerMemoryBytes 8GB` で変更できます。
アプリ VM の IOPS 上限は [gp3 の標準スループット](https://docs.aws.amazon.com/ebs/latest/userguide/general-purpose.html) 125 MiB/s を 8 KiB で割った 16,000 です。
CPU は `HwThreadCountPerCore=2` で SMT の構成を公開します。物理コアへの固定や本番と同じ性能を保証する設定ではありません。[Microsoft の説明](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/manage/manage-hyper-v-scheduler-types)

## 構築オプション

各回の `build.ps1` の主な引数です。

| 引数 | 既定値 | 説明 |
| :--- | :--- | :--- |
| `-IsoPath` | 必須 | 対応する Ubuntu Server ISO |
| `-OutputPath` | 必須 | VM、SSH 鍵、ログの保存先 |
| `-ApplicationName` | `<大会>-app01`〜`app03` | アプリ VM 名を 3 つ指定 |
| `-BenchmarkerName` | `<大会>-bench` | ベンチ VM 名 |
| `-SwitchName` | `Default Switch` | インターネット接続用の仮想スイッチ |
| `-InternalSwitchName` | `ISUCON13` / `ISUCON14` | 新規作成する固定 IP 用の Internal Switch |
| `-NetworkPrefix` | 大会別手順に記載 | 固定 IP 用のプライベート IPv4 CIDR（/29 以下） |
| `-MemoryBytes` | `4GB` | アプリ VM 1 台あたりの固定メモリ |
| `-BenchmarkerMemoryBytes` | `4GB` | ベンチ VM の固定メモリ |
| `-ProcessorCount` | `2` | 構築後のアプリ VM の vCPU 数 |
| `-BenchmarkerProcessorCount` | `8` | 構築後のベンチ VM の vCPU 数 |
| `-TimeoutMinutes` | `45` | VM ごとの Ubuntu インストール待ち時間 |

旧引数名 `-MemoryMaximumBytes` / `-BenchmarkerMemoryMaximumBytes` も同じ固定メモリ指定のエイリアスとして利用できます。
固定 IP 用のスイッチは既存のものを再利用しません。同名のスイッチがある場合は `-InternalSwitchName` に別名を指定してください。
既存の IP、経路、WinNAT とアドレス帯が重複する場合は、`-NetworkPrefix` で重複しない CIDR に変更してください。

## SSH 接続

共通の SSH 鍵は `$outputPath\ssh\id_ed25519` に生成されます。保存先、接続する VM 名を指定して接続します。

```powershell
$outputPath = 'D:\isucon13'
$vmName = 'isucon13-app01' # 接続する大会・VM に合わせて変更
$vmIP = (Get-VMNetworkAdapter -VMName $vmName -Name isucon).IPAddresses |
    Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } |
    Select-Object -First 1
$knownHosts = Join-Path $outputPath "ssh\known_hosts_$vmName"
ssh -i (Join-Path $outputPath 'ssh\id_ed25519') `
    -o "HostKeyAlias=$vmName" `
    -o "UserKnownHostsFile=`"$knownHosts`"" `
    "ubuntu@$vmIP"
```

SSH・アプリ・ベンチの通信には `isucon` NIC の固定 IP を使用します。インターネット接続用 NIC は別のスイッチで DHCP を使用します。
競技ユーザーで作業する場合は、接続後に `sudo -iu isucon` を実行します。

## プロビジョニングの再実行

対象大会のフォルダーにある `provision.ps1` を使用します。VM は起動しておいてください。
この処理にはビルドツールの導入・撤去、公式ソース取得、ローカル用の設定変更、アセットのビルド、TLS 証明書生成、公式 Ansible、CPU・IOPS の再設定が含まれます。
アプリ用 VM に再実行すると、DB・アプリ・TLS 証明書が初期化されます。
`-ProcessorCount` の既定値はアプリ 2 / ベンチ 8 です。構築後の CPU 数を変更している場合は、再実行時にも指定してください。
`-IdentityFile` で SSH 秘密鍵のパスを指定することもできます。

## 生成物

`-OutputPath` で指定したフォルダーに以下を保存します。

- `vm/`：VM 設定、VHDX、NoCloud の seed ISO
- `ssh/`：共通 SSH 鍵、VM ごとの known_hosts
- `logs/`：ISO 生成ログ、`provision-<VM名>-<日時>.log`

ゲストへ転送した構築処理は `/home/ubuntu/provision-isucon13.sh` または `/home/ubuntu/provision-isucon14.sh`、公式ソースは `/home/ubuntu/isucon13` または `/home/ubuntu/isucon14`、競技用アプリとベンチバイナリは `/home/isucon` に配置します。
