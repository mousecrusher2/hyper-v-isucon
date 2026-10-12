# Hyper-V ISUCON 検証環境

ISUCON の各回を Hyper-V 上に構築するスクリプトです。各回のフォルダーに構築手順、インストール設定、provision をまとめています。

| 大会 | 使用する ISO | 手順 | 構築入口 |
| :--- | :--- | :--- | :--- |
| ISUCON13 | Ubuntu Server 22.04 (amd64) | [ISUCON13](isucon13/README.md) | `isucon13/build.ps1` |
| ISUCON14 | Ubuntu Server 24.04 (amd64) | [ISUCON14](isucon14/README.md) | `isucon14/build.ps1` |

[共通の前提条件・VM 仕様・SSH 接続](docs/common.md) を確認し、管理者権限の PowerShell 7.3 以上で実行してください。ISO のパスは手元のファイル名に合わせてください。

```powershell
.\isucon13\build.ps1 -IsoPath 'D:\iso\ubuntu-22.04-live-server-amd64.iso' -OutputPath 'D:\isucon13'
.\isucon14\build.ps1 -IsoPath 'D:\iso\ubuntu-24.04-live-server-amd64.iso' -OutputPath 'D:\isucon14'
```

## 配置

```text
isucon13/
  README.md          構築・Web・ベンチマーク・再実行の手順
  build.ps1          ISUCON13 の VM 4 台を構築
  install.ps1        ISUCON13 の OS インストール
  autoinstall.yaml   ISUCON13 のインストール設定
  verify.sh          OS・UEFI・swap・SSH の初回起動確認
  provision.ps1      ISUCON13 のゲスト構築を SSH で実行
  provision.sh       ISUCON13 のパッケージ・ビルド・TLS・Ansible 処理
  validation.md      検証記録
isucon14/            ISUCON14 の同じ構成
common/
  hyperv/            ネットワーク・VM・仮想ハードウェア・資源設定
  guest/             SSH 鍵・接続待機・コマンド実行・ファイル転送
  iso/               xorriso コンテナ・NoCloud ISO 生成
  ubuntu/            Ubuntu インストール ISO の autoinstall 化
  engine/            インストール・provision・複数 VM 構築の実行手順
docs/
  common.md          前提条件・VM 仕様・オプション・SSH 接続
```

各回が `autoinstall.yaml`、`verify.sh`、`provision.sh` と VM 名・ネットワーク・マシンスペックを所有します。`build.ps1`、`install.ps1`、`provision.ps1` がこれらを共通エンジンに渡します。
共通エンジンは Hyper-V・SSH・NoCloud ISO の操作と実行順序を担当します。OS 名・バージョン・大会の選択引数は持たず、渡された検証スクリプトと構築コマンドの終了コードを確認します。Ubuntu 用の ISO 加工処理は各回の入口が明示的に指定します。

## 参考

各回で構築入口と provision を持つ配置、パッケージ準備・アセットのビルド・公式 Ansible 適用の流れは、以下を参考にしています。

- [wsl-isucon](https://github.com/matsuu/wsl-isucon)
- [vagrant-isucon](https://github.com/matsuu/vagrant-isucon)

各回の README に対応する構築スクリプトへのリンクがあります。Hyper-V の 3 台＋ベンチ 1 台の構成に合わせて、固定 IP・DNS・決済サーバーの接続先を設定しています。
