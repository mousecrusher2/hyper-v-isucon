# ISUCON13

[Ubuntu Server 22.04 公式 ISO (amd64)](https://releases.ubuntu.com/22.04/) を使い、本番同様にアプリ VM 3 台＋ベンチ VM 1 台を構築します。前提条件は [トップの README](../README.md#前提条件) を参照してください。

## 構成

| 項目 | アプリ VM（3 台） | ベンチ VM（1 台） |
| :--- | :--- | :--- |
| VM 名 | `isucon13-app01` 〜 `isucon13-app03` | `isucon13-bench` |
| 固定 IP | `192.168.13.2` 〜 `192.168.13.4` | `192.168.13.5` |
| スペック / 台 | 2 vCPU / 4 GiB メモリ / 40 GiB ディスク | 8 vCPU / 4 GiB メモリ / 40 GiB ディスク |

### 必要リソース（既定値）

- メモリ: 計 16 GiB（ベンチ VM を本番同様の 8 GiB にする場合は計 20 GiB）
- ディスク: 最大計 160 GiB（可変容量）
- CPU: 合計 14 vCPU

### ネットワーク・ドメイン

- **内部ネットワーク**: Internal Switch `ISUCON13` を作成し、Windows 側は `192.168.13.1` で接続します。インターネット接続には `Default Switch` を使います。
- **ドメイン / TLS**: `*.u.isucon.test` / `*.t.isucon.test` を使用します。同梱の固定証明書チェーン（サーバー証明書 → 中間 CA → ルート CA の 3 枚）を配信します。

## 構築

管理者権限の PowerShell 7 で実行します。

```powershell
$outputPath = 'D:\isucon13'
.\isucon13\build.ps1 `
    -IsoPath 'D:\iso\ubuntu-22.04-live-server-amd64.iso' `
    -OutputPath $outputPath
```

`$outputPath` 配下に VM（VHDX）、SSH 鍵、構築ログが保存されます。

### オプション引数

| 引数 | 既定値 | 用途 |
| :--- | :--- | :--- |
| `-BenchmarkerMemoryBytes 8GB` | `4GB` | ベンチ VM のメモリを本番同様の 8 GiB に増量 |
| `-NetworkPrefix '192.168.x.0/24'` | `192.168.13.0/24` | アドレス帯が競合する場合に変更 |
| `-InternalSwitchName '<名前>'` | `ISUCON13` | 仮想スイッチ名が競合する場合に変更 |

仮想スイッチ名には未使用の名前、アドレス帯には既存ネットワークや VPN の経路と重ならない範囲を指定してください。既定値が競合する場合は、上記の引数で変更できます。

## SSH 接続

```powershell
$outputPath = 'D:\isucon13'
$vmName = 'isucon13-app01'
$vmIP = '192.168.13.2'
ssh -i "$outputPath\ssh\id_ed25519" `
    -o "HostKeyAlias=$vmName" `
    -o "UserKnownHostsFile=`"$outputPath\ssh\known_hosts_$vmName`"" `
    "ubuntu@$vmIP"
```

- 他の VM は `$vmName` と `$vmIP` を変更してください。
- 競技ユーザーへの切替: `sudo -iu isucon`（作業ディレクトリ: `/home/isucon/webapp`）

## Web アプリの確認

ブラウザで確認する場合は、Windows の `C:\Windows\System32\drivers\etc\hosts` に以下を追加して `https://pipe.u.isucon.test/` にアクセスします（証明書の警告は無視して続行）。

```text
192.168.13.2 pipe.u.isucon.test
```

hosts を編集せずに CLI で確認する場合:

```powershell
curl.exe --noproxy '*' --insecure --resolve pipe.u.isucon.test:443:192.168.13.2 https://pipe.u.isucon.test/
```

## ベンチマーク

`isucon13-bench` に SSH 接続して実行します（`--nameserver` は対象アプリ VM の IP）。

```bash
cd /home/ubuntu/isucon13/bench
/home/isucon/bench_linux_amd64 run \
  --nameserver 192.168.13.2 --enable-ssl
```

- 初期化・整合性チェックのみ: `--pretest-only` を追加
- 結果出力先: `/tmp/result.json`

## プロビジョニングの再実行

対象 VM を起動した状態で実行します。**※ アプリ VM の DB・コード・証明書は初期化されます。**

```powershell
$outputPath = 'D:\isucon13'
# アプリ VM
.\isucon13\provision.ps1 -VMName 'isucon13-app01' -OutputPath $outputPath

# ベンチ VM
.\isucon13\provision.ps1 -VMName 'isucon13-bench' -OutputPath $outputPath -Role benchmarker
```

ログは `$outputPath\logs` に保存されます。

## ローカル環境用の調整

- **プロビジョニング**: `provision.sh` 内でアプリは `application.yml`、ベンチは `benchmark.yml` を実行します。
- **一時ビルドツール**: ビルド用に Go 1.21 や Node.js 20 / Corepack を一時インストールし、撤去後に公式 Ansible で各言語ランタイムを導入します。
- **ドメイン / DNS**: `isucon.dev` を `isucon.test` に置換し、PowerDNS には内部 NIC（`isucon`）の固定 IP を登録します。
- **TLS**: 本番と同じ鍵種別（u: ECDSA P-256、t: RSA 2048）の固定証明書を配置します。ベンチマーカー側の検証は省略します。
- **VM リソース**: 作成時から指定の vCPU と IOPS 制限を適用し、プロビジョニング時のリソース切り替えや再起動は行いません。
- **io_uring 回避**: Ubuntu 22.04（Linux 5.15）での Node.js ビルド停止を避けるため、`UV_USE_IO_URING=0` を設定します。

## TLS チェーンの再現

`tls/` にローカル検証用の固定証明書チェーンとサーバー秘密鍵を同梱しています。有効期限は 2046 年です。プロビジョニング時に転送して nginx の TLS ディレクトリへコピーし、3 枚のチェーンを配信します。`_.u.isucon.test.issuer.crt` には後ろ 2 枚を格納しています。CA の秘密鍵は同梱しません。

## 参考

- [公式 ISUCON13](https://github.com/isucon/isucon13)
