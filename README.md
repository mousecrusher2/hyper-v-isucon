# Hyper-V ISUCON 検証環境

ISUCON の過去問を、Hyper-V 上にアプリ VM 3 台＋ベンチマーク VM 1 台の構成で自動構築するスクリプトです。

OS インストール後は仮想ディスクを起動順の先頭に設定します。DVD ドライブと生成した ISO は残します。不要になったら、Hyper-V マネージャーで DVD ドライブを削除し、ISO ファイルを手動で削除してください。

| 大会 | 手順 |
| :--- | :--- |
| ISUCON13 | [isucon13/README.md](isucon13/README.md) |
| ISUCON14 | [isucon14/README.md](isucon14/README.md) |

## 前提条件

- Windows 10 / 11（Hyper-V を有効化済み）
- PowerShell 7.3 以上（管理者権限で実行）
- Windows OpenSSH Client
- WSLC を利用できる WSL 2.9.3 以上（`wslc version` で確認）
- VM 4 台分のメモリ（既定で計 16 GiB）とディスク（可変長で最大計 160 GiB）、インターネット接続
