# ISUCON14 検証記録

確認日: 2026-10-12（JST）

構築入口は `build.ps1`、インストール処理は `install.ps1`、ゲスト構築は `provision.ps1` と `provision.sh` です。
設定は同じフォルダーの `autoinstall.yaml`、初回起動の確認基準は `verify.sh` に置き、Ubuntu Server 24.04 を使用します。手順は [README](README.md) を参照してください。

PowerShell・シェルの構文、共通エンジンと同一フォルダー内のファイル参照を確認しています。
Hyper-V・SSH・WSLC の操作を差し替え、seed 生成、インストール順序、アプリ・ベンチ用の CPU・SMT・IOPS 設定、転送・OS 検証の失敗伝播、並列ジョブへの引数渡し、コンテナ起動失敗時の元 ISO 保持を確認しました。
Hyper-V 上での無人インストール、全言語のビルド、Web アプリとベンチマークの実機実行は未検証です。
