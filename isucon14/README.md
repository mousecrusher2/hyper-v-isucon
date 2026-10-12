# ISUCON14

Ubuntu Server 24.04 の公式 ISO を使い、アプリ VM 3 台とベンチ VM 1 台を構築します。前提条件・共通仕様・オプションは [共通手順](../docs/common.md) を参照してください。

## 大会別の設定

| 項目 | 設定 |
| :--- | :--- |
| Ubuntu / autoinstall | 24.04 / `autoinstall.yaml` |
| アプリ VM 名 | `isucon14-app01`〜`isucon14-app03` |
| ベンチ VM 名 | `isucon14-bench` |
| Internal Switch | `ISUCON14` |
| 固定 IP | Windows `.1`、アプリ `.2`〜`.4`、ベンチ `.5`（`192.168.14.0/24`） |
| ローカルドメイン | `*.xiv.isucon.test` / `xiv.isucon.test` |
| TLS サーバー鍵 | RSA 2048 ビット（自己署名） |

## 構築

管理者権限の PowerShell から実行します。ISO のパスは手元のファイル名に合わせてください。

```powershell
$outputPath = 'D:\isucon14'
.\isucon14\build.ps1 `
    -IsoPath 'D:\iso\ubuntu-24.04-live-server-amd64.iso' `
    -OutputPath $outputPath
```

このフォルダーの `autoinstall.yaml` を使用します。Ubuntu Server 24.04 の ISO を指定してください。

## SSH 接続

[共通の接続手順](../docs/common.md#ssh-接続) で `$outputPath = 'D:\isucon14'`、`$vmName = 'isucon14-app01'` 等を指定します。アプリの作業ディレクトリは `/home/isucon/webapp` で、初期状態では `isuride-go.service` が動作します。

## Web アプリの確認

Windows の hosts ファイル（`C:\Windows\System32\drivers\etc\hosts`）に追加し、`https://isuride.xiv.isucon.test/` にアクセスします。
自己署名証明書を使うため、ブラウザの警告画面でアクセスを続行してください。

```text
192.168.14.2 isuride.xiv.isucon.test
```

```powershell
curl.exe --noproxy '*' --insecure --resolve isuride.xiv.isucon.test:443:192.168.14.2 https://isuride.xiv.isucon.test/
```

アドレス帯を変更した場合は、hosts と curl の IP を対象 VM の固定 IP に置き換えます。

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

`--addr` は対象アプリ VM の固定 IP とポート、`--payment-url` はアプリから到達できるベンチ VM の IP です。
ベンチマーカーは実行中に TCP 12345 で決済サーバーも起動します。`localhost` はアプリ VM 自身を指すため、ベンチ VM の固定 IP を指定します。
接続先を `--addr` で指定するので、ベンチ VM の hosts 編集は不要です。初期化と整合性確認のみの場合は `-t 0` に変更します。結果は標準出力・標準エラーに表示します。
静的ファイルと公式ベンチ同梱ハッシュが一致しない場合は、[公式 README](https://github.com/isucon/isucon14) に従って `--skip-static-sanity-check` を追加できます。この場合は静的ファイルの取得も省略され、本番の負荷とは異なります。

## プロビジョニングの再実行

対象 VM を起動した状態で、管理者権限の PowerShell から実行します。

```powershell
$outputPath = 'D:\isucon14'
.\isucon14\provision.ps1 -VMName 'isucon14-app01' -OutputPath $outputPath
.\isucon14\provision.ps1 -VMName 'isucon14-bench' -OutputPath $outputPath -Role benchmarker
```

アプリ VM の DB・アプリ・証明書は初期化されます。ログと引数の詳細は [共通手順](../docs/common.md#プロビジョニングの再実行) を参照してください。

## ローカル環境用の調整

- ゲスト固有処理は `provision.sh` です。アプリは `application-base.yml` → `application.yml`、ベンチは `benchmark.yml` を実行します。
- フロントエンドの準備には Node.js 22 と pnpm 9、ベンチの準備には Go 1.23 を使用します。準備用ツールを撤去してから公式 Ansible を実行します。
- Ubuntu 24.04 の deb822 APT 設定に合わせて、公式のパッケージ準備処理の対象パスを変更します。
- `xiv.isucon.net` を `xiv.isucon.test` に置き換え、自己署名証明書を生成します。アプリ内で証明書を信頼させ、`isuride-matcher` がローカル HTTPS API に接続できるようにします。
- ベンチマーカー側は自己署名証明書の検証を省略します。フロントエンドは再実行時にも `webapp/public` へファイルをコピーします。
- 大会運営者用の `isuadmin-user` と AWS ポータル向けの `envcheck` ロールは省略します。

## 検証

[ISUCON14 の検証記録](validation.md) を参照してください。構文・ファイル参照を確認しています。Hyper-V 上での無人インストール・全言語ビルド・ベンチマークは未検証です。

## 参考

- [公式 ISUCON14](https://github.com/isucon/isucon14)
- [大会当日マニュアル](https://github.com/isucon/isucon14/blob/main/docs/manual.md)
- [wsl-isucon の構築例](https://github.com/matsuu/wsl-isucon/blob/main/isucon14/scripts/01-provisioning.sh)

- [vagrant-isucon の構築例](https://github.com/matsuu/vagrant-isucon/blob/master/isucon14-standalone/Vagrantfile)
