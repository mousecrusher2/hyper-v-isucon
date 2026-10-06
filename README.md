# Hyper-V ISUCON13 検証環境

Hyper-V 上に ISUCON13 の競技環境（アプリ用 VM 3 台、ベンチマーク用 VM 1 台）を自動構築する PowerShell スクリプトです。
Ubuntu Server 22.04 の公式 ISO から無人インストールを行い、公式 Ansible を適用してローカル検証環境をセットアップします。

- **対象ドメイン**: `*.u.isucon.test` / `*.t.isucon.test`
- **TLS 証明書**: 自己署名証明書（自動生成）

---

## 前提条件

実行前に、以下の環境・ソフトウェアをご用意ください。

- **OS**: Windows 10 / 11（Hyper-V を有効化済みであること）
- **PowerShell**: PowerShell 7.3 以上（※管理者権限で実行してください）
- **SSH クライアント**: Windows OpenSSH Client
- **WSL**: WSLC を利用できる WSL 2.9.3 以上（`wslc version` で確認可能）
- **Ubuntu ISO**: [Ubuntu Server 22.04 LTS (amd64)](https://releases.ubuntu.com/22.04/) のインストーラー ISO

---

## VM 構成（既定値）

| 項目 | アプリ用 VM (`app01`〜`app03`) | ベンチマーク用 VM (`bench`) |
| :--- | :--- | :--- |
| **台数** | 3 台 | 1 台 |
| **VM 名** | `isucon13-app01`  `isucon13-app02`  `isucon13-app03` | `isucon13-bench` |
| **固定 IP** | `192.168.13.2`〜`.4` (/24) | `192.168.13.5` (/24) |
| **vCPU** | 各 2 vCPU（1 コア × 2 スレッド） | 8 vCPU（4 コア × 2 スレッド） |
| **メモリ** | 固定 4 GiB | 固定 4 GiB |
| **swap** | 無効 | 無効 |
| **ディスク** | 各 40 GiB (VHDX) | 40 GiB (VHDX) |
| **IOPS 制限** | 最大 16,000 IOPS（8 KiB 換算） | 制限なし |
| **ログインユーザー** | `ubuntu`（SSH 公開鍵認証 / `sudo` パスワード不要） | 同左 |

> [!NOTE]
> 構築中は一時的に全 VM を 4 vCPU / IOPS 制限なしで起動してプロビジョニングを行い、Ansible 完了後に上記の CPU 数と IOPS 制限へ自動設定されます。

アプリ用 VM の IOPS 上限は、[gp3 の標準スループット](https://docs.aws.amazon.com/ebs/latest/userguide/general-purpose.html) 125 MiB/s を 8 KiB で割った 16,000 に設定しています。

CPU は `HwThreadCountPerCore=2` で 1 コアあたり 2 スレッドの SMT 構成に設定します。Windows 10 / 11 の既定の Root スケジューラーでは Windows 側がスケジューリングを行うため、この指定だけで物理コアへの固定や本番と同じ CPU 性能は保証できません。[Microsoft の説明](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/manage/manage-hyper-v-scheduler-types)

ベンチマーク用 VM のメモリは、本番の 8 GiB から 4 GiB に減らしています。必要に応じて、利用者自身で VM を停止し、Hyper-V マネージャーでメモリを 8 GiB に変更できます。

---

## 構築手順

管理者権限で PowerShell 7 を開き、リポジトリのルートディレクトリから以下のスクリプトを実行します。

```powershell
$outputPath = 'D:\isucon13'
.\scripts\New-Isucon13VM.ps1 `
    -IsoPath 'D:\iso\ubuntu-22.04.5-live-server-amd64.iso' `
    -OutputPath $outputPath
```

- `-IsoPath`: ダウンロードした Ubuntu Server 22.04 ISO のパスを指定します。
- `-OutputPath`: VM の仮想ディスク、SSH 鍵、ログ等を保存するフォルダーを指定します（フォルダーは自動作成されます）。

正常に終了すると、4 台すべての VM が構築・起動された状態になります。

### 主なオプション

必要に応じて以下のオプションを追加できます。

| オプション | 既定値 | 説明 |
| :--- | :--- | :--- |
| `-NetworkPrefix` | `192.168.13.0/24` | 内部固定 IP のアドレス帯。既存ネットワークと競合してエラーになる場合に変更します。 |
| `-SwitchName` | `Default Switch` | インターネット接続（DHCP）に使用する Hyper-V 仮想スイッチ名。 |
| `-ApplicationName` | `'isucon13-app01', ...` | アプリ用 VM 名（3 つ指定）。 |
| `-BenchmarkerName` | `'isucon13-bench'` | ベンチマーク用 VM 名。 |
| `-ProcessorCount` | `2` | 構築後のアプリ用 VM の vCPU 数。 |
| `-BenchmarkerProcessorCount` | `8` | 構築後のベンチマーク用 VM の vCPU 数。 |

---

## VM への SSH 接続

構築時に `$outputPath\ssh` 配下へ共通の SSH 秘密鍵（`id_ed25519`）が生成されます。
PowerShell から以下のスクリプトで接続できます。

```powershell
$outputPath = 'D:\isucon13'
$vmName = 'isucon13-app01' # または 'isucon13-app02', 'isucon13-app03', 'isucon13-bench'

$vmIP = (Get-VMNetworkAdapter -VMName $vmName -Name isucon).IPAddresses |
    Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } |
    Select-Object -First 1

$knownHosts = Join-Path $outputPath "ssh\known_hosts_$vmName"
ssh -i (Join-Path $outputPath 'ssh\id_ed25519') `
    -o "HostKeyAlias=$vmName" `
    -o "UserKnownHostsFile=`"$knownHosts`"" `
    "ubuntu@$vmIP"
```

> [!TIP]
> アプリ用 VM で `isucon` ユーザーとして作業する場合は、SSH 接続後に `sudo -iu isucon` を実行してください。

---

## 動作確認（Web アプリ）

### 1. hosts ファイルの登録

Windows ホストのブラウザからアクセスするために、管理者権限でメモ帳等を開き、`C:\Windows\System32\drivers\etc\hosts` にアプリ用 VM の IP アドレスとドメインを追加します。

```text
192.168.13.2 pipe.u.isucon.test
```

※ アドレス帯を変更した場合は、該当 VM の固定 IP を指定してください。

### 2. ブラウザからのアクセス

ブラウザで以下の URL を開きます。

- **URL**: `https://pipe.u.isucon.test/`

自己署名証明書を使用しているためブラウザに警告が表示されますが、アクセスを続行してください。

PowerShell から curl で応答を確認する場合は以下を実行します：

```powershell
curl.exe --noproxy '*' --insecure --resolve pipe.u.isucon.test:443:192.168.13.2 https://pipe.u.isucon.test/
```

---

## ベンチマークの実行

1. ベンチマーク用 VM（`isucon13-bench`）に SSH 接続します。
2. 接続先のシェルでベンチマークを実行します（`--nameserver` にはテスト対象のアプリ VM の IP を指定します）。

```bash
cd /home/ubuntu/isucon13/bench
/home/isucon/bench_linux_amd64 run \
  --nameserver 192.168.13.2 --enable-ssl
```

- 初期化と整合性チェックのみを行う場合は `--pretest-only` を追加します。
- 負荷ベンチマークの実行結果は `/tmp/result.json` に保存されます。

---

## トラブルシューティング

### Ansible プロビジョニングに失敗した場合の再実行

Ubuntu のインストール完了後に Ansible プロビジョニングで失敗した場合は、対象 VM を起動した状態で以下のスクリプトを実行することで、プロビジョニングのみを再実行できます。

**アプリ用 VM の場合:**

```powershell
$outputPath = 'D:\isucon13'
$vmName = 'isucon13-app01'
.\scripts\Invoke-Isucon13Ansible.ps1 -VMName $vmName -OutputPath $outputPath
```

※ アプリ用 VM で再実行すると、DB および TLS 証明書が初期化されます。

**ベンチマーク用 VM の場合:**

```powershell
$outputPath = 'D:\isucon13'
.\scripts\Invoke-Isucon13Ansible.ps1 -VMName 'isucon13-bench' -OutputPath $outputPath -Role benchmarker
```

### ネットワークの重複エラーが出る場合

「指定したアドレス帯が既存のネットワークと重複しています」というエラーが表示された場合は、ホストの既存ネットワークや WinNAT と競合しています。
`-NetworkPrefix` オプションで重複しない別のアドレス帯（例: `-NetworkPrefix '192.168.213.0/24'`）を指定して再実行してください。

---

## 生成物の配置

`-OutputPath` で指定したフォルダーには以下のファイルが生成されます。

- `vm/`: 各 VM の仮想ハードディスク（VHDX）および設定
- `ssh/`: 共通 SSH 秘密鍵（`id_ed25519`）および接続ログ（known_hosts）
- `logs/`: ISO 生成ログや Ansible 実行ログ

---

## 参考リンク

- [実機検証記録](docs/validation.md)
- [公式 ISUCON13 リポジトリ](https://github.com/isucon/isucon13)
- [vagrant-isucon (matsuu/vagrant-isucon)](https://github.com/matsuu/vagrant-isucon/blob/master/isucon13-standalone/Vagrantfile)
- [wsl-isucon (matsuu/wsl-isucon)](https://github.com/matsuu/wsl-isucon/blob/main/isucon13/scripts/01-provisioning.sh)
