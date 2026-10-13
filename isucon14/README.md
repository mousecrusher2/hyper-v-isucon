# ISUCON14

[Ubuntu Server 24.04 の公式 ISO (amd64)](https://releases.ubuntu.com/24.04/) を使い、アプリ VM 3 台とベンチ VM 1 台を構築します。前提条件は [トップの README](../README.md#前提条件) を参照してください。

## 構成

| 項目 | アプリ VM | ベンチ VM |
| :--- | :--- | :--- |
| VM 名 | `isucon14-app01`〜`isucon14-app03` | `isucon14-bench` |
| 固定 IP | `192.168.14.2`〜`.4` | `192.168.14.5` |
| vCPU / メモリ / ディスク | 2 / 4 GiB / 40 GiB | 8 / 4 GiB / 40 GiB |

- Windows 側は Internal Switch `ISUCON14` に `192.168.14.1` で接続します。インターネット接続は `Default Switch` を使います。
- ローカルドメインは `*.xiv.isucon.test` / `xiv.isucon.test` で、TLS 証明書はローカル CA が発行します（RSA 2048 ビット）。本番と同じ 2 枚の証明書チェーンを配信します。

## 構築

管理者権限の PowerShell から実行します。ISO のパスは手元のファイル名に合わせてください。

```powershell
$outputPath = 'D:\isucon14'
.\isucon14\build.ps1 `
    -IsoPath 'D:\iso\ubuntu-24.04-live-server-amd64.iso' `
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
$outputPath = 'D:\isucon14'
$vmName = 'isucon14-app01'
$vmIP = '192.168.14.2'
ssh -i "$outputPath\ssh\id_ed25519" `
    -o "HostKeyAlias=$vmName" `
    -o "UserKnownHostsFile=`"$outputPath\ssh\known_hosts_$vmName`"" `
    "ubuntu@$vmIP"
```

他の VM に接続する場合は、[構成](#構成) の表に合わせて `$vmName` と `$vmIP` を変更します。競技ユーザーで作業する場合は、接続後に `sudo -iu isucon` を実行します。アプリの作業ディレクトリは `/home/isucon/webapp` で、初期状態では `isuride-go.service` が動作します。

## Web アプリの確認

Windows の hosts ファイル（`C:\Windows\System32\drivers\etc\hosts`）に追加し、`https://isuride.xiv.isucon.test/` にアクセスします。
ローカル CA を Windows 側では信頼していないため、ブラウザの警告画面でアクセスを続行してください。

```text
192.168.14.2 isuride.xiv.isucon.test
```

```powershell
curl.exe --noproxy '*' --insecure --resolve isuride.xiv.isucon.test:443:192.168.14.2 https://isuride.xiv.isucon.test/
```

## ベンチマーク

`isucon14-bench` に SSH 接続して実行します。

```bash
cd /home/ubuntu/isucon14/bench
/home/isucon/bench_linux_amd64 run \
  --target https://isuride.xiv.isucon.test \
  --addr 192.168.14.2:443 \
  --payment-url http://192.168.14.5:12345 \
  --fail-on-error -t 60
```

- `--addr` は対象アプリ VM の固定 IP です。接続先をこれで指定するので、ベンチ VM の hosts 編集は不要です。
- `--payment-url` はベンチ VM の固定 IP です。ベンチマーカーは実行中に TCP 12345 で決済サーバーを起動し、アプリ VM からここに接続させます。
- 初期化と整合性確認のみの場合は `-t 0` に変更します。
- 静的ファイルと公式ベンチ同梱ハッシュが一致しない場合は、[公式 README](https://github.com/isucon/isucon14) に従って `--skip-static-sanity-check` を追加できます。この場合は静的ファイルの取得も省略され、本番の負荷とは異なります。

## プロビジョニングの再実行

アプリやベンチを構築し直す場合は、対象 VM を起動した状態で管理者権限の PowerShell から実行します。**アプリ VM の DB・アプリ・証明書は初期化されます。**

```powershell
$outputPath = 'D:\isucon14'
.\isucon14\provision.ps1 -VMName 'isucon14-app01' -OutputPath $outputPath
.\isucon14\provision.ps1 -VMName 'isucon14-bench' -OutputPath $outputPath -Role benchmarker
```

ログは `$outputPath\logs` に保存します。

## ローカル環境用の調整

- ゲスト固有処理は `provision.sh` です。アプリは `application-base.yml` → `application.yml`、ベンチは `benchmark.yml` を実行します。
- フロントエンドの準備には Node.js 22 と pnpm 9、ベンチの準備には Go 1.23 を使用します。準備用ツールを撤去してから公式 Ansible を実行します。
- Ubuntu 24.04 の deb822 APT 設定に合わせて、公式のパッケージ準備処理の対象パスを変更します。
- `xiv.isucon.net` を `xiv.isucon.test` に置き換え、ローカル CA から証明書を発行します。`isuride-matcher` の `curl` に `-k` を付けて証明書検証を省略し、ローカル HTTPS API に接続できるようにします。
- ベンチマーカー側はローカル CA の証明書検証を省略します。フロントエンドは再実行時にも `webapp/public` へファイルをコピーします。
- 大会運営者用の `isuadmin-user` と AWS ポータル向けの `envcheck` ロールは省略します。

## TLS チェーンの再現

ローカルのルート CA（RSA 4096 ビット）と中間 CA（RSA 2048 ビット）を作り、サーバー証明書（RSA 2048 ビット）→ 中間 CA の 2 枚を nginx から配信します。サーバー証明書の鍵方式とチェーンの枚数を本番に合わせ、チェーンを含む通信量を再現します。`isuride-matcher` は `curl -k` で接続します。

証明書には CA 制約、鍵用途、ホスト名など接続に必要な拡張を設定し、生成時に OpenSSL で署名とホスト名を検証します。CA の秘密鍵はプロビジョニング終了時に一時ディレクトリとともに削除します。デフォルトサーバー用の `dummy.crt` は本番と同じ ECDSA P-256 で生成します。

## 動作確認状況

構文・ファイル参照のみ確認しています。Hyper-V 上での無人インストール・全言語ビルド・ベンチマークは未検証です。

TLS 生成処理は一時的な wslc コンテナ内で検証しています。nginx が 2 枚のチェーンを配信すること、署名・ホスト名の検証、`curl -k` による HTTPS 接続を確認しました。

## 参考

- [公式 ISUCON14](https://github.com/isucon/isucon14)
- [大会当日マニュアル](https://github.com/isucon/isucon14/blob/main/docs/manual.md)
