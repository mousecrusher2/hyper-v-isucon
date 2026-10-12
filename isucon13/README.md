# ISUCON13

Ubuntu Server 22.04 の公式 ISO を使い、アプリ VM 3 台とベンチ VM 1 台を構築します。前提条件・共通仕様・オプションは [共通手順](../docs/common.md) を参照してください。

## 大会別の設定

| 項目 | 設定 |
| :--- | :--- |
| Ubuntu / autoinstall | 22.04 / `autoinstall.yaml` |
| アプリ VM 名 | `isucon13-app01`〜`isucon13-app03` |
| ベンチ VM 名 | `isucon13-bench` |
| Internal Switch | `ISUCON13` |
| 固定 IP | Windows `.1`、アプリ `.2`〜`.4`、ベンチ `.5`（`192.168.13.0/24`） |
| ローカルドメイン | `*.u.isucon.test` / `*.t.isucon.test` |
| TLS サーバー鍵 | u：ECDSA P-256、t：RSA 2048 ビット（自己署名） |

## 構築

管理者権限の PowerShell から実行します。ISO のパスは手元のファイル名に合わせてください。

```powershell
$outputPath = 'D:\isucon13'
.\isucon13\build.ps1 `
    -IsoPath 'D:\iso\ubuntu-22.04-live-server-amd64.iso' `
    -OutputPath $outputPath
```

このフォルダーの `autoinstall.yaml` を使用します。Ubuntu Server 22.04 の ISO を指定してください。

## SSH 接続

[共通の接続手順](../docs/common.md#ssh-接続) で `$outputPath = 'D:\isucon13'`、`$vmName = 'isucon13-app01'` 等を指定します。アプリの作業ディレクトリは `/home/isucon/webapp` です。

## Web アプリの確認

Windows の hosts ファイル（`C:\Windows\System32\drivers\etc\hosts`）に追加し、`https://pipe.u.isucon.test/` にアクセスします。
自己署名証明書を使うため、ブラウザの警告画面でアクセスを続行してください。

```text
192.168.13.2 pipe.u.isucon.test
```

```powershell
curl.exe --noproxy '*' --insecure --resolve pipe.u.isucon.test:443:192.168.13.2 https://pipe.u.isucon.test/
```

アドレス帯を変更した場合は、hosts と curl の IP を対象 VM の固定 IP に置き換えます。

## ベンチマーク

`isucon13-bench` に SSH 接続して実行します。`--nameserver` は対象アプリ VM の固定 IP です。

```bash
cd /home/ubuntu/isucon13/bench
/home/isucon/bench_linux_amd64 run \
  --nameserver 192.168.13.2 --enable-ssl
```

初期化と整合性確認のみの場合は `--pretest-only` を追加します。負荷ベンチマークの結果は `/tmp/result.json` に保存します。

## プロビジョニングの再実行

対象 VM を起動した状態で、管理者権限の PowerShell から実行します。

```powershell
$outputPath = 'D:\isucon13'
.\isucon13\provision.ps1 -VMName 'isucon13-app01' -OutputPath $outputPath
.\isucon13\provision.ps1 -VMName 'isucon13-bench' -OutputPath $outputPath -Role benchmarker
```

アプリ VM の DB・アプリ・証明書は初期化されます。ログと引数の詳細は [共通手順](../docs/common.md#プロビジョニングの再実行) を参照してください。

## ローカル環境用の調整

- ゲスト固有処理は `provision.sh` です。アプリは `application.yml`、ベンチは `benchmark.yml` を実行します。
- ビルド準備に Go 1.21、アプリ用には Node.js 20 と Corepack を使用し、撤去後に公式 Ansible が各言語のランタイムを導入します。
- `isucon.dev` を `isucon.test` に置き換え、PowerDNS の登録には `isucon` NIC の固定 IP を使います。
- 自己署名証明書を生成し、ベンチマーカー側では証明書検証を省略します。
- Ubuntu 5.15 カーネルでの Node/libuv ビルド停止を避けるため、`UV_USE_IO_URING=0` を設定し、Ansible の sudo にも引き継ぎます。

## 検証

[ISUCON13 の検証記録](validation.md) を参照してください。旧配置での実機検証記録を保存しています。今回の配置変更後は構文・ファイル参照を確認しています。実機の再構築は未実施です。

## 参考

- [公式 ISUCON13](https://github.com/isucon/isucon13)
- [vagrant-isucon の構築例](https://github.com/matsuu/vagrant-isucon/blob/master/isucon13-standalone/Vagrantfile)
- [wsl-isucon の構築例](https://github.com/matsuu/wsl-isucon/blob/main/isucon13/scripts/01-provisioning.sh)
