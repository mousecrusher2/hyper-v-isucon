# ISUCON13

[Ubuntu Server 22.04 の公式 ISO (amd64)](https://releases.ubuntu.com/22.04/) を使い、アプリ VM 3 台とベンチ VM 1 台を構築します。前提条件は [トップの README](../README.md#前提条件) を参照してください。

## 構成

| 項目 | アプリ VM | ベンチ VM |
| :--- | :--- | :--- |
| VM 名 | `isucon13-app01`〜`isucon13-app03` | `isucon13-bench` |
| 固定 IP | `192.168.13.2`〜`.4` | `192.168.13.5` |
| vCPU / メモリ / ディスク | 2 / 4 GiB / 40 GiB | 8 / 4 GiB / 40 GiB |

- Windows 側は Internal Switch `ISUCON13` に `192.168.13.1` で接続します。インターネット接続は `Default Switch` を使います。
- ローカルドメインは `*.u.isucon.test` / `*.t.isucon.test` で、TLS 証明書はローカル CA が発行します。本番と同じ 3 枚の証明書チェーンを配信します。

## 構築

管理者権限の PowerShell から実行します。ISO のパスは手元のファイル名に合わせてください。

```powershell
$outputPath = 'D:\isucon13'
.\isucon13\build.ps1 `
    -IsoPath 'D:\iso\ubuntu-22.04-live-server-amd64.iso' `
    -OutputPath $outputPath
```

`$outputPath` に VM・SSH 鍵・ログを保存します。必要に応じて以下の引数を追加します。

| 引数 | 用途 |
| :--- | :--- |
| `-BenchmarkerMemoryBytes 8GB` | ベンチ VM のメモリを本番と同じ 8 GiB にする |
| `-NetworkPrefix '192.168.x.0/24'` | 既存ネットワークとアドレス帯が重なる場合に変更する |
| `-InternalSwitchName '<名前>'` | 同名の仮想スイッチが既にある場合に変更する |

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

他の VM に接続する場合は、[構成](#構成) の表に合わせて `$vmName` と `$vmIP` を変更します。競技ユーザーで作業する場合は、接続後に `sudo -iu isucon` を実行します。アプリの作業ディレクトリは `/home/isucon/webapp` です。

## Web アプリの確認

Windows の hosts ファイル（`C:\Windows\System32\drivers\etc\hosts`）に追加し、`https://pipe.u.isucon.test/` にアクセスします。
ローカル CA を Windows 側では信頼していないため、ブラウザの警告画面でアクセスを続行してください。

```text
192.168.13.2 pipe.u.isucon.test
```

```powershell
curl.exe --noproxy '*' --insecure --resolve pipe.u.isucon.test:443:192.168.13.2 https://pipe.u.isucon.test/
```

## ベンチマーク

`isucon13-bench` に SSH 接続して実行します。`--nameserver` は対象アプリ VM の固定 IP です。

```bash
cd /home/ubuntu/isucon13/bench
/home/isucon/bench_linux_amd64 run \
  --nameserver 192.168.13.2 --enable-ssl
```

初期化と整合性確認のみの場合は `--pretest-only` を追加します。負荷ベンチマークの結果は `/tmp/result.json` に保存します。

## プロビジョニングの再実行

アプリやベンチを構築し直す場合は、対象 VM を起動した状態で管理者権限の PowerShell から実行します。**アプリ VM の DB・アプリ・証明書は初期化されます。**

```powershell
$outputPath = 'D:\isucon13'
.\isucon13\provision.ps1 -VMName 'isucon13-app01' -OutputPath $outputPath
.\isucon13\provision.ps1 -VMName 'isucon13-bench' -OutputPath $outputPath -Role benchmarker
```

ログは `$outputPath\logs` に保存します。

## ローカル環境用の調整

- ゲスト固有処理は `provision.sh` です。アプリは `application.yml`、ベンチは `benchmark.yml` を実行します。
- ビルド準備に Go 1.21、アプリ用には Node.js 20 と Corepack を使用し、撤去後に公式 Ansible が各言語のランタイムを導入します。
- `isucon.dev` を `isucon.test` に置き換え、PowerDNS の登録には `isucon` NIC の固定 IP を使います。
- 本番に合わせた鍵方式（u：ECDSA P-256、t：RSA 2048 ビット）でローカル CA から証明書を発行し、ベンチマーカー側では証明書検証を省略します。
- Ubuntu 5.15 カーネルでの Node/libuv ビルド停止を避けるため、`UV_USE_IO_URING=0` を設定し、Ansible の sudo にも引き継ぎます。

## TLS チェーンの再現

ローカルのルート CA（RSA 4096 ビット）と中間 CA（RSA 2048 ビット）を作り、サーバー証明書 → 中間 CA → ルート CA の 3 枚を nginx から配信します。`_.u.isucon.test.issuer.crt` には後ろの 2 枚を保存します。サーバー証明書の鍵方式とチェーンの枚数を本番に合わせ、チェーンを含む通信量を再現します。

証明書には CA 制約、鍵用途、ホスト名など接続に必要な拡張を設定し、生成時に OpenSSL で署名とホスト名を検証します。CA の秘密鍵はプロビジョニング終了時に一時ディレクトリとともに削除します。

## 動作確認状況

旧フォルダー構成では Hyper-V 上での実機構築を確認しています。現在のフォルダー構成に変更した後は構文・ファイル参照のみ確認しており、実機での再構築は未実施です。

TLS 生成処理は一時的な wslc コンテナ内で検証しています。nginx が 3 枚のチェーンを配信すること、署名・ホスト名の検証を確認しました。

## 参考

- [公式 ISUCON13](https://github.com/isucon/isucon13)
