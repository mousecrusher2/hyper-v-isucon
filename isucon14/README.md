# ISUCON14

[Ubuntu Server 24.04 公式 ISO (amd64)](https://releases.ubuntu.com/24.04/) を使い、本番同様にアプリ VM 3 台＋ベンチ VM 1 台を構築します。前提条件は [トップの README](../README.md#前提条件) を参照してください。

## 構成

| 項目 | アプリ VM（3 台） | ベンチ VM（1 台） |
| :--- | :--- | :--- |
| VM 名 | `isucon14-app01` 〜 `isucon14-app03` | `isucon14-bench` |
| 固定 IP | `192.168.14.2` 〜 `192.168.14.4` | `192.168.14.5` |
| スペック / 台 | 2 vCPU / 4 GiB メモリ / 40 GiB ディスク | 8 vCPU / 4 GiB メモリ / 40 GiB ディスク |

### 必要リソース（既定値）

- メモリ: 計 16 GiB（ベンチ VM を本番同様の 8 GiB にする場合は計 20 GiB）
- ディスク: 最大計 160 GiB（可変容量）
- CPU: 合計 14 vCPU

### ネットワーク・ドメイン

- **内部ネットワーク**: Internal Switch `ISUCON14` を作成し、Windows 側は `192.168.14.1` で接続します。インターネット接続には `Default Switch` を使います。
- **ドメイン / TLS**: `*.xiv.isucon.test` / `xiv.isucon.test` を使用します。同梱の固定証明書チェーン（サーバー証明書 RSA 2048 → 中間 CA の 2 枚）を配信します。

## 構築

管理者権限の PowerShell 7 で実行します。新規構築用のため、出力先には未使用のディレクトリを指定してください。

```powershell
$outputPath = 'D:\isucon14'
.\isucon14\build.ps1 `
    -IsoPath 'D:\iso\ubuntu-24.04-live-server-amd64.iso' `
    -OutputPath $outputPath
```

`$outputPath` 配下に VM（VHDX）、SSH 鍵、構築ログが保存されます。

### オプション引数

| 引数 | 既定値 | 用途 |
| :--- | :--- | :--- |
| `-BenchmarkerMemoryBytes 8GB` | `4GB` | ベンチ VM のメモリを本番同様の 8 GiB に増量 |
| `-NetworkPrefix '192.168.x.0/24'` | `192.168.14.0/24` | アドレス帯が競合する場合に変更 |
| `-InternalSwitchName '<名前>'` | `ISUCON14` | 仮想スイッチ名が競合する場合に変更 |

仮想スイッチ名には未使用の名前、アドレス帯には既存ネットワークや VPN の経路と重ならない範囲を指定してください。既定値が競合する場合は、上記の引数で変更できます。

## SSH 接続

```powershell
$outputPath = 'D:\isucon14'
$vmName = 'isucon14-app01'
$vmIP = '192.168.14.2'
ssh -i "$outputPath\ssh\id_ed25519" `
    -o "HostKeyAlias=$vmName" `
    -o "UserKnownHostsFile=`"$outputPath\ssh\known_hosts_$vmName`"" `
    "ubuntu@$vmIP"
```

- 他の VM は `$vmName` と `$vmIP` を変更してください。
- 競技ユーザーへの切替: `sudo -iu isucon`（作業ディレクトリ: `/home/isucon/webapp`、初期状態は Go 版が稼働）

## Web アプリの確認

ブラウザで確認する場合は、Windows の `C:\Windows\System32\drivers\etc\hosts` に以下を追加して `https://isuride.xiv.isucon.test/` にアクセスします（証明書の警告は無視して続行）。

```text
192.168.14.2 isuride.xiv.isucon.test
```

hosts を編集せずに CLI で確認する場合:

```powershell
curl.exe --noproxy '*' --insecure --resolve isuride.xiv.isucon.test:443:192.168.14.2 https://isuride.xiv.isucon.test/
```

## ベンチマーク

`isucon14-bench` に SSH 接続して実行します。

```bash
/home/isucon/bench_linux_amd64 run \
  --target https://isuride.xiv.isucon.test \
  --addr 192.168.14.2:443 \
  --payment-url http://192.168.14.5:12345 \
  --fail-on-error -t 60
```

- `--addr`: 対象アプリ VM の IP:PORT（ベンチ VM の hosts 編集は不要）
- `--payment-url`: 決済サーバー URL（ベンチ VM の IP で TCP 12345 を待ち受け）
- `-t 0`: 初期化・整合性チェックのみ
- `--skip-static-sanity-check`: 静的ファイルのハッシュ不一致時にスキップ（静的ファイル取得も省略されます）

## ローカル環境用の調整

- **プロビジョニング**: `provision.sh` 内でアプリは `application-base.yml` → `application.yml`、ベンチは `benchmark.yml` を実行します。
- **一時ビルドツール**: Node.js 22 / pnpm 9、Go 1.23、Task を一時インストールし、公式の `make_latest_files.sh` で配布物を生成します。ツールを撤去後、公式 Ansible を実行します。
- **APT 設定**: Ubuntu 24.04 の deb822 設定（`ubuntu.sources`）に合わせて対象パスを調整しています。
- **ドメイン / 証明書**: `xiv.isucon.net` を `xiv.isucon.test` に置換し、固定証明書を配置します。`isuride-matcher` の `curl` には `-k` を付与します。
- **VM リソース**: 作成時から指定の vCPU と IOPS 制限を適用し、プロビジョニング時のリソース切り替えや再起動は行いません。
- **ベンチ / 静的ファイル**: ベンチマーカーの証明書検証は公式実装の既定動作で省略されます。
- **除外ロール**: 運営用の `isuadmin-user` と AWS 向けの `envcheck` は除外しています。

## TLS チェーンの再現

`tls/` にローカル検証用の固定証明書チェーンとサーバー秘密鍵を同梱しています。有効期限は 2046 年です。プロビジョニング時に転送して nginx の TLS ディレクトリへコピーし、2 枚のチェーンを配信します。フォールバック用の `dummy.crt` は ECDSA P-256 です。CA の秘密鍵は同梱しません。

## 参考

- [公式 ISUCON14](https://github.com/isucon/isucon14)
