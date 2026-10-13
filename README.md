# Hyper-V ISUCON 検証環境

ISUCON の過去問を、本番同様の複数台構成（競技用 VM 複数台＋ベンチマーク専用 VM 1 台）で Hyper-V 上に自動構築するスクリプトです（単一 VM の簡易環境ではありません）。

## 対応大会

| 大会 | 構成 | 詳細 |
| :--- | :--- | :--- |
| ISUCON13 | アプリ VM 3 台 ＋ ベンチ VM 1 台 | [isucon13/README.md](isucon13/README.md) |
| ISUCON14 | アプリ VM 3 台 ＋ ベンチ VM 1 台 | [isucon14/README.md](isucon14/README.md) |

## 前提条件

- Windows 10 / 11（Hyper-V 有効化済み）
- PowerShell 7.3 以上（管理者権限）
- Windows OpenSSH Client
- WSL 2.9.3 以上（WSLC 利用可能、`wslc version` で確認）
- 対象大会の VM 群を動かせる CPU / メモリ / ディスク（詳細は各大会の README を参照）
- インターネット接続
