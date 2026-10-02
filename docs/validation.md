# 実機検証記録

検証日: 2026-09-30・2026-10-01・2026-10-02（JST）

## 現行構成

`New-Isucon13VM.ps1`で、アプリ用3台・ベンチ用1台をISOから並列に無人インストールし、
各VMに役割に応じた公式Ansibleを実行する。構築中は全VMで4 vCPU・最小メモリ2 GiB・IOPS制限なし。
各VMのAnsible成功後に、最小メモリを512 MiBへ戻し、アプリ用は2 vCPU・最大32000 IOPS、ベンチ用は8 vCPU・IOPS制限なしに設定する。
Internal Switch側の固定IPをSSH・アプリ・ベンチの通信とDNS登録に使用する。
インターネット接続は別NICのDHCPを使用する。
構築スクリプトはWindowsの管理者権限を必須とする。
Windows側の仮想NICにも固定IPを設定し、同じアドレス帯にVMの固定IPを割り当てる。
固定IP用のInternal Switchは構築時に必ず新規作成し、同名の既存スイッチは再利用せずエラーにする。
既定値は`192.168.13.0/24`、Windows側は`.1`、アプリ用VMは`.2`〜`.4`、ベンチ用VMは`.5`。
アドレス帯は`NetworkPrefix`で変更できる。既存IP・経路・WinNATと重複したら設定前にエラーにする。

### 準備完了後のネットワーク作成（2026-10-02）

構築順を「SSH鍵の準備 → インストール用ISOの準備 → 固定IP用ネットワークの作成 → VM4台の構築」に変更した。
SSH鍵やISOの準備で失敗しても、スイッチとWindows側の固定IPを作成しない。

コマンドを代替し、SSH鍵生成失敗・ISO準備失敗・ネットワーク作成失敗・正常終了の4件を確認した。
準備失敗時はネットワーク処理を呼ばないこと、正常時はネットワーク作成後に4台の処理を開始して各固定IPを渡すこと、
ISO準備以降の失敗時も一時ISOを削除することを確認した。PowerShellの構文チェックも通った。
実際のHyper-V構築は再実行していない。VM・ディスク・スイッチは作成していない。
検証用の作業フォルダーは削除済み。記録は`.local/checks/preparation-order-20261002/result.log`。

### 固定IP用スイッチの新規作成（2026-10-02）

既存Internal Switchを再利用する処理を削除した。
`InternalSwitchName`は新規作成する名前として扱い、同名の既存スイッチがある場合は設定変更前に停止する。
新しいWindows側の仮想NICへは毎回`New-NetIPAddress`を呼び、`PolicyStore`を省略して有効・永続の両方に固定IPを登録する。
既存IP・有効経路・永続経路・WinNATとの重複検査と、ネットワーク設定失敗時の作成済みスイッチ削除は継続する。

コマンドを代替した23件の確認が通った。ActiveStoreにしかIPがない場合を含め、同名の既存スイッチを変更せず拒否すること、
新規作成時の固定IP登録、重複検出、設定失敗時の削除を確認した。PowerShellの構文チェックも通った。
実際のHyper-V構築・Windows再起動後の通信は再検証していない。VM・ディスク・スイッチは作成していない。
記録は`.local/checks/admin-network-20261002/network-new-switch.log`。

### 固定IPの重複エラーメッセージ（2026-10-02）

重複エラーを「指定したアドレス帯が既存のネットワークと重複しています」という表現に統一した。
指定したアドレス帯と、検出した相手の名前・アドレス帯、または経路を表示する。
READMEの案内も「既存ネットワークとの重複」に変更した。
既存IP・有効経路・永続経路・WinNATの検査は継続する。
WinNATがない状態での既存IP・経路との重複と、WinNATとの包含関係を含む重複について、コマンドを代替した確認を再実行した。
この変更ではVM・ディスク・スイッチを作成していない。

### 旧方式: 管理者権限必須・既存スイッチの再利用を含む固定IP設定（2026-10-02）

`New-Isucon13VM.ps1`・`Initialize-IsuconNetwork.ps1`・`New-UbuntuVM.ps1`・`Invoke-Isucon13Ansible.ps1`に、
`#requires -RunAsAdministrator`を追加した。非管理者の実行セッションから4本を呼び出し、すべて`ScriptRequiresElevation`で処理開始前に停止することを確認した。

ネットワーク処理は、Windows側の自動IPを読み取る方式から固定IPを設定する方式へ変更した。
`New-NetIPAddress`の`PolicyStore`を省略して、ActiveStoreとPersistentStoreの両方に保存する構成にした。
ゲートウェイは指定しない。既存IPは接続状態やアドレス状態で除外せず、経路は有効・永続の両方を検査する。デフォルトルートは重複検査対象から除外する。

権限宣言だけを除いた検証用コピーでネットワークコマンドを代替し、次を確認した。

| 確認 | 結果 |
| --- | --- |
| 既定値とカスタム`/29` | Windows側は先頭の使用可能IP、VM4台は続く4つを使用 |
| 保存方法 | IP設定時に`PolicyStore`とゲートウェイを指定しない |
| 再利用 | 固定IPが一致する既存Internal SwitchではIPを再追加しない。自動IPの既存スイッチには固定IPを追加 |
| 既存設定の保護 | 異なる固定IP、他のVMが接続されたスイッチ、Internal以外のスイッチを変更前に拒否 |
| IP・WinNATの重複 | 未接続NICの暫定IPも検査し、包含関係を含む重複を変更前に拒否 |
| 経路の重複 | IPが存在しなくても、ActiveStore・PersistentStoreそれぞれの重複経路を検出 |
| 設定前の読み取り失敗 | スイッチとIPを変更せず停止 |
| 設定失敗・IP利用可能待機のタイムアウト | この処理が作成したスイッチだけを削除 |

変更したPowerShellの構文も確認した。
この実行セッションは非管理者のため、実際のWindows側IP設定・永続化・固定IP経由のSSHは今回未検証。
VM・ディスク・スイッチは作成していない。公式Ansible全体と負荷ベンチも再実行していない。
記録は`.local/checks/admin-network-20261002/`の`admin-guard.json`・`network.log`。

### 初回起動前の自動MAC取得（2026-10-02）

ディスクなしのGeneration 2 VMを作成し、2枚のNICをDefault Switchへ接続した。
VMを一度も起動せずに`Get-VMNetworkAdapter`で確認したところ、両NICとも`DynamicMacAddressEnabled=True`、`MacAddress=000000000000`だった。
`Set-VMNetworkAdapter -DynamicMacAddress`を明示してから再取得しても同じ値だった。
したがって、このPCでは作成直後にMACを読むだけではautoinstallのNIC識別条件に使える値を取得できなかった。
この検証時点では固定MAC生成を維持した。続く起動後の検証により、以下の方式へ変更した。

検証用VMは所有IDを照合して削除し、既存VM一覧が変わらないことを確認した。
VMは起動しておらず、VHDX・ISO・新しいスイッチは作成していない。VMの設定用フォルダーも削除済み。
記録は`.local/checks/mac-beforeboot-20261002/`の`before-start.json`・`cleanup.json`。

### 空ディスクでの起動によるMAC割り当て（2026-10-02）

空の4Kn VHDXを持つGeneration 2 VMと2枚のNICを作成し、インストール用ISOを接続せずに起動した。
起動直後に電源を切るだけでは、両NICともMACが`000000000000`のままだった。
再起動後に有効なMACが揃うまで待つと、両NICに異なるMACが割り当てられた。空ディスクだけを起動対象にした検証でも、取得まで約4秒だった。
電源断後もMACが保持されることと、取得した値を固定MACへ設定した後の再起動でも同じ値を使うことを確認した。

`New-UbuntuVM.ps1`の自前MAC生成を削除し、空ディスクで起動して割り当てを待つ方式へ変更した。
30秒で取得できなければ停止してエラーにする。取得後に電源を切り、Hyper-Vが割り当てたMACを固定してからseedを生成する。
インストール用ISOはこの処理の後に接続する。CPU・メモリ・VSS・コンソール・自動開始停止の設定は、この最初の起動前から適用する。

検証用VM・VHDX・設定フォルダーは所有IDとパスを照合して削除し、既存VM一覧が変わらないことを確認した。
この検証ではUbuntuのインストールと公式Ansibleを再実行していない。
記録は`.local/checks/mac-boot-20261002/`の`immediate.json`・`macs.json`・`cleanup.json`。

### 固定MACの自前生成へ変更（2026-10-02）

MAC取得のための追加起動・待機・電源断を削除した。
OSの乱数生成器で6バイトを取得し、先頭バイトのGroupビットを0、Localビットを1にして、ローカル管理用ユニキャストMACとして固定する。
残り46ビットが乱数となる。取得できる既存VM・管理OSのNICのMACと重複した場合は再生成する。
並列処理間の予約や排他制御は行わないため、同時生成の衝突確率そのものはゼロにはならない。

一様かつ独立な乱数を前提に、VM4台・NIC8枚のいずれかが衝突する確率の上限は、`8 × 7 / 2 ÷ 2^46 ≈ 3.98 × 10^-13`（約2.5兆分の1）。
同じ生成範囲の既存MACが1000個ある場合も含めると、上限は`(8 × 1000 + 28) ÷ 2^46 ≈ 1.14 × 10^-10`（約88億分の1）。
以前の`02`固定＋40ビット乱数では、8枚同士の上限が約393億分の1だった。

PowerShellの構文と乱数APIの実行、生成MACのビット設定・文字列形式を確認した。
既存VM・管理OSのMACを実機で取得できることも確認した。この変更の検証ではVMを作成せず、Ubuntuのインストールと公式Ansibleは再実行していない。

### 旧方式: 未接続NICの暫定IPを重複検査から除外（2026-10-02）

初期の検査が重複として検出した`169.254.224.134/16`は、`ローカル エリア接続* 9`（Microsoft Wi-Fi Direct Virtual Adapter #2）のものだった。
同NICは`Disconnected`、IPは`Tentative`で、IPv4のActiveStoreに169.254帯の経路は存在しなかった。
FSE Switch側の`vEthernet (FSE HostVnic)`にはIPv4アドレスがなく、重複検出対象ではなかった。

検査対象を、接続中のNICにある`Preferred`または`Deprecated`のIPv4に変更した。
コマンドを代替して、未接続NICと`Tentative`のIPを除外し、接続中の有効IPとの重複は引き続きエラーになることを確認した。
既存WinNATの範囲の検査は継続する。

変更後の実機検証では、検証用Internal SwitchのWindows側に自動設定された`169.254.233.8/16`を読み取り、
VM4台分に`169.254.1.1`〜`.4`を割り当てた。Windows側に169.254帯の接続先経路ができることも確認した。
検証後に作成したスイッチを削除し、既存スイッチ・IPv4アドレス・WinNATが変わらないことを確認した。
この確認ではVMとディスクは作成していない。VMへのSSH・公式Ansible全体・負荷ベンチは未確認。
記録は`.local/checks/automatic-network-20261002/network-current.log`と`native-current.json`。

### 旧方式: Windows側の自動IPを使用した初期の重複検査（2026-10-02）

`Initialize-IsuconNetwork.ps1`で検証専用Internal Switchを作成し、WindowsがIPv4を自動設定するまで待機した。
このPCでは、既存の`ローカル エリア接続* 9`に`169.254.224.134/16`が存在するため、
新しいスイッチのアドレス帯との重複を検出してエラーになった。
自動作成した検証用スイッチが削除されたことと、既存スイッチ・IPv4アドレス・WinNATが変わらないことを確認した。

コマンドを代替した確認では、次を検証した。

| 確認 | 結果 |
| --- | --- |
| 自動IPからの割り当て | Windows側`169.254.42.100/16`を読み、VMへ`169.254.1.1`〜`.4`を割り当て。予約された先頭256アドレスを使用しない |
| Windows側IPの除外 | Windows側が`169.254.1.1`の場合、VMには`.2`〜`.5`を割り当て |
| 指定済みスイッチ | Windows側`192.168.213.3/29`を読み、`.1`・`.2`・`.4`・`.5`を割り当て。スイッチとIP設定を変更しない |
| 重複検査 | 他NICとの同一帯・包含関係、WinNATとの包含関係を検出。利用可能になる前の既存IPv4も検査対象 |
| エラー時の削除 | 自動作成したスイッチだけを削除。指定済みのスイッチは保持 |
| IPv4待機・読み取り失敗 | エラーで終了し、自動作成したスイッチを削除 |
| 4台の並列処理 | 固定IP・`/16`・2つのスイッチ・CPU・メモリ設定を各子処理へ引き継ぎ |
| AnsibleのSSH待機 | `isucon` NICの`169.254.1.1`を、資源変更の前後とも接続先として選択 |

Windows側IPを追加・変更するコマンドを使用しない構成へ変更した。
通常の構築コマンドで`-InternalSwitchName`を指定した場合は、既存のスイッチを要求する。
今回の実機ではアドレス帯の重複により停止するため、新構成でのVM作成・公式Ansible全体・負荷ベンチは実行していない。
Linux 5.15の公式`hv_kvp_daemon.c`では、IPv4通知時に169.254帯を除外する処理がないことを確認した。
公式ISUCON13のソース`8f6afdc3603f0c661368de4659a7240862f59623`のアプリ・ベンチ・Ansibleを検索し、169.254帯を拒否するIP判定は見つからなかった。

検証用スイッチと、コマンド代替確認で生成したISO・SSH鍵・作業用フォルダーは削除した。検証用VMは作成していない。
記録は`.local/checks/automatic-network-20261002/`の`network.log`・`native.json`・`orchestration.log`・`ssh.log`に保存した。

### 旧方式: Windows側の固定IP設定（2026-10-02）

検証用Internal SwitchとUbuntu Server 22.04.5のVM2台を作成した。
ホストの固定IP設定はWindowsの管理者権限不足で拒否されたため、SSHはDefault Switch側から行った。
ホスト固定IPでのSSHと、構築スクリプト全体の正常終了は今回確認できていない。
固定IP用ネットワークの設定失敗が後続処理を中断することは確認した。

初回の大文字MAC表記では、インストール後の起動時にNIC設定が適用されなかった。
MACを小文字に統一してISOから作り直した2台では、次を確認した。

| 確認 | 結果 |
| --- | --- |
| 無人インストール | ISOからインストール・poweroff・DVD解除・ディスク起動 |
| 固定IP | `isucon` NICに192.168.13.2 / 192.168.13.3 |
| VM間通信 | 固定IPを送信元にして相手VMのSSHへTCP接続 |
| インターネット | `uplink` NICのDHCP経路。APTでAnsibleを取得 |
| デフォルトルート | IPv4はDHCP側の1本のみ。固定IP側にはなし |
| 公式env.shテンプレート | `ansible_isucon.ipv4.address`で192.168.13.2を出力。DHCP側IPと異なることをAnsibleで確認 |
| 資源変更後の再起動 | 各2 vCPU・最小512 MiB・最大32000 IOPSへ変更して再起動。固定IP・VM間通信・テンプレート出力を維持 |
| Netplanの維持 | 再起動前後のファイルのSHA-256が一致 |

再起動でDHCP側は172.31.79.188 → 172.31.70.24、172.31.73.42 → 172.31.65.157に変わったが、固定IP側は変わらなかった。
検証時のバージョンはcloud-init `25.1.4-0ubuntu0~22.04.1`、netplan.io `0.106.1-7ubuntu0.22.04.4`、systemd `249.11-0ubuntu3.22`。

インストーラは`90-installer-network.cfg`を生成し、cloud-initが`50-cloud-init.yaml`を生成する構成だった。
最終autoinstallには、初回生成後にネットワーク設定の再生成を無効にする`user-data.write_files`を追加した。
この追加はVMのインストール後に行ったため、最終user-dataのスキーマと既定モジュールへの登録を確認し、
実際のcloud-initの`write_files`モジュールを単体実行してファイルを生成した。最終設定でのISOからの再インストールは行っていない。
その後の通常再起動では生成済みNetplan設定が維持された。

代替したネットワーク情報で、WinNATが候補サブネットを含む場合・候補がWinNATを含む場合・ホストのアドレス帯と重複する場合に、
変更前に停止することを確認した。カスタム`/29`でのIP割り当ても確認した。
4台の子処理を代替した確認では、固定IPの重複なし、スイッチ2つ・プレフィックス長・CPU・メモリの引き継ぎと並列実行を確認した。
公式`application.yml`・`benchmark.yml`全体と負荷ベンチは再実行していない。

検証用VM2台・VHDX・ISO・SSH鍵・Internal Switchは所有IDとパスを照合して削除した。
既存の`uefi-test`、Default Switch、FSE Switchは保持し、WinNATは変更していない。

記録:

- `.local/checks/network-20261002/ranges.log`
- `.local/checks/network-20261002/orchestration.log`
- `.local/checks/network-20261002/verify-before-restart.log`
- `.local/checks/network-20261002/verify-after-restart.log`
- `.local/checks/network-20261002/template.log`
- `.local/checks/network-20261002/host-ip-check.json`
- `.local/checks/network-20261002/cleanup.json`

### 構築中の最小メモリ（2026-10-02）

新規VMを初回起動前から最小2 GiBに設定するよう変更した。
Ansibleの再実行でも、CPU数または最小メモリが構築用の値と異なる場合は停止して4 vCPU・最小2 GiBへ変更する。
成功後の停止中に最小メモリを512 MiBへ戻す。失敗時は構築用の設定を保持する。
起動時メモリ・最大メモリの設定は維持する。

変更したPowerShellの構文と差分を確認した。この変更では実機VMや公式Ansibleを実行していない。

### 事前ビルド用ツールの導入・削除（2026-10-02）

`preparation-tools-check-20261002`へUbuntu Server 22.04.5を無人インストールした。
変更後の`provision-isucon13.sh`をそのまま使用し、アプリ用・ベンチ用を順に実行した。
公式Ansibleの呼び出し先だけを検査コマンドに置き換え、事前ビルドの完了と呼び出し時点の状態を確認した。

| 確認 | 結果 |
| --- | --- |
| 準備用Go | Snapの1.21/stableから1.21.13を導入 |
| 準備用Node.js | NodeSourceの20系から20.20.2を導入 |
| アプリ用の事前ビルド | 公式`make_latest_files.sh`でベンチ・フロントエンド・環境確認プログラム・webappアーカイブを生成 |
| ベンチ用の事前ビルド | `make -C bench linux_amd64`でベンチバイナリを生成 |
| Ansible呼び出し時点 | GoのSnapは削除済み。Go・Node.js・npm・Corepack・Yarnのコマンドは存在せず、ビルド成果物とAnsible本体は存在 |
| NodeSourceの設定 | APTのソース設定・鍵を削除済み |
| 検証後の削除 | 所有VM IDを照合して検証用VM・VHDX・ISOを削除。既存VM5台は保持 |

既知のNodeヒープ上限の問題と切り分けるため、事前ビルドの検証時だけ最小メモリを2 GiBに設定した。
この検証時点では、構築スクリプトの最小メモリは512 MiBだった。公式Ansible本体の実行と4台の並列構築は、この検証には含めていない。

記録:

- `.local/checks/preparation-tools-20261002/application.log`
- `.local/checks/preparation-tools-20261002/benchmarker.log`
- `.local/checks/preparation-tools-20261002/test-memory.json`
- `.local/checks/preparation-tools-20261002/cleanup-result.json`

### WSLCによるISO生成と入力なしのインストール（2026-10-01）

`New-AutoinstallIso.ps1`で、WSLCの公式`ubuntu:26.04`を一時コンテナとして起動した。
コンテナ内で`apt-get update`・`apt-get upgrade -y`を実行してからxorrisoをインストールした。
実際に3パッケージが更新され、更新を保留したパッケージは0だった。xorrisoのバージョンは1.5.6。

`ubuntu-22.04.5-live-server-amd64.iso`からGRUB設定とチェックサム一覧を取り出し、
メニュー待ち時間の解除と各カーネル起動引数への`autoinstall`追加、チェックサム更新を行った。
xorrisoの`-boot_image any replay`でUEFI・BIOS起動情報を引き継いでISOを生成し、
書き戻した設定とチェックサム一覧を再度読み出して一致を確認した。
ISOとスクリプトの読み取り専用マウント、空白を含むWindows側の出力先も使用できた。

変更後の`New-UbuntuVM.ps1`を使い、`wslc-iso-check-20261001`を構築した。
検証時はVM作成直後に所有IDを記録する処理だけ追加し、インストール処理は変更していない。
ISO生成からディスク再起動・SSH接続まで318秒で完了した。仮想キーボードによる入力処理は使用していない。

| 確認 | 結果 |
| --- | --- |
| OS・起動方式 | Ubuntu 22.04・UEFI |
| CPU・メモリ | 4 vCPU・動的メモリ（起動2 GiB、最小512 MiB、最大4 GiB） |
| ディスク | 40 GiB・4Kn VHDX、ルートはext4、LVMなし |
| 管理ユーザー | `ubuntu`、指定ホスト名、公開鍵SSH・passwordless sudo成功 |
| SSHパスワード認証 | 無効 |
| cloud-init | `done`、errors・recoverable_errorsなし |
| インストーラーの起動引数 | `BOOT_IMAGE=/casper/vmlinuz autoinstall ---` |
| メディアのチェックサム | `pass`、不一致なし |
| 使用済みのインストールISO | DVD解除後にスクリプトが削除 |

`New-Isucon13VM.ps1`の子処理を代替した検証では、ISO生成が一度だけ呼ばれ、
4つの並列ジョブへ同じ加工済みISOを渡すことを確認した。
正常終了時には共有ISOを削除し、失敗したVMがまだISOを使用している場合は保持する。
1台のインストールが失敗した場合も、残る3台の処理は完了した。
この変更では公式Ansibleの再実行と4台の実機インストールは行っていない。

検証用VM・VHDX・加工ISOは削除済み。一時コンテナも終了後に削除された。
元のUbuntu ISOは検証前後のSHA-256が一致し、既存の`uefi-test`は停止状態のまま保持した。

記録:

- `.local/checks/wslc-iso/iso-build.log`
- `.local/checks/wslc-iso/install.log`
- `.local/checks/wslc-iso/guest-check.log`
- `.local/checks/wslc-iso/install-result.json`
- `.local/checks/wslc-iso/orchestration.log`
- `.local/checks/wslc-iso/cleanup-result.json`

### 初回起動前のコンソール無効化（2026-10-01）

`Disable-VMConsoleSupport`を最初の`Start-VM`より前へ移し、
`console-off-check-20261001`でISO生成から無人インストール・SSH接続まで確認した。
インストール中、仮想ディスプレイ・キーボード・マウスがすべて0件であることを確認した。
326.9秒で完了し、UEFI・sudo・cloud-init・メディアのチェックサムも正常だった。
検証用VM・VHDX・使用済みISOは削除済み。元のISOと既存VMは保持した。

記録:

- `.local/checks/console-before-install/console-during-install.json`
- `.local/checks/console-before-install/install-result.json`
- `.local/checks/console-before-install/guest-check.log`
- `.local/checks/console-before-install/cleanup-result.json`

### 保存先の指定（2026-10-01）

3つのスクリプトに必須の`-OutputPath`を追加し、指定先の`vm/`・`ssh/`・`logs/`へ出力する構成に変更した。
Hyper-V操作とゲスト実行を代替し、実際のスクリプトで次を確認した。

- 相対パス・末尾の区切り文字・空白を含む保存先で、VMのディスク・設定のパスが指定先になる。
- NoCloudの設定とseed ISO、SSH鍵、Ansibleログが指定先に生成される。seed ISOはWindowsのIMAPIで実際に生成した。
- Windows OpenSSHが空白を含む鍵・接続先記録のパスを設定として受け付ける。
- Ansibleの再実行で同じ鍵を使用し、異なる保存先を指定した場合はSSH実行前にエラーになる。
- 4つの並列ジョブで、両段階へ同じ絶対パスの保存先を引き継ぐ。

この変更では実際のVM作成・OSインストール・公式Ansibleの再実行は行っていない。
VMとVHDXは作成していない。

記録: `.local/results/output-path-check.log`

### Ubuntuの直接インストール

`New-UbuntuVM.ps1`を使い、`direct-install-check-01`へUbuntuを直接インストールした。
ISOは`D:\iso\ubuntu-22.04.5-live-server-amd64.iso`、VMはGeneration 2・2 vCPU・固定4 GiB。
インストール、ISO解除、ディスクからの起動まで無人で完了した。

起動確認用のSSHコマンドでCRLFの問題が見つかったため、LFに統一する処理を追加した。
同じVMでSSH・passwordless sudo・cloud-init正常完了・指定ホスト名・minimal構成・LVMなし・SSHパスワード認証無効を確認した。

`direct-install-check-01`での実機確認範囲はUbuntuの起動確認まで。
公式Ansible・HTTPS・DNSの結果は、下記の同じminimal構成での検証記録を参照。

検証用VMとディスクは削除済み。

記録:

- `.local/results/direct-install-build.log`
- `.local/results/direct-install-check.log`
- `.local/results/direct-install-cleanup.json`

### 並列構築とCPU・IOPSの後設定（2026-10-01）

変更したPowerShellスクリプトで、下記4台を同じISOから並列に無人インストールした。
この検証ではAnsibleのゲスト処理を、CPU数・sudo・cloud-init・4Knを確認する処理に置き換えた。
VM作成・インストール・SSH接続・正常シャットダウン・資源設定・再起動は実際の処理を使用した。

| VM | 構築中のvCPU / 最大IOPS | 完了後のvCPU / 最大IOPS | 固定メモリ |
| --- | --- | --- | --- |
| `parallel-check-app01` | 4 / 0（制限なし） | 2 / 32000 | 4 GiB |
| `parallel-check-app02` | 4 / 0（制限なし） | 2 / 32000 | 4 GiB |
| `parallel-check-app03` | 4 / 0（制限なし） | 2 / 32000 | 4 GiB |
| `parallel-check-bench` | 4 / 0（制限なし） | 8 / 0（制限なし） | 8 GiB |

4台が同時にRunningになり、構築中のCPU・IOPSが表の値であることをホストから確認した。
各ゲストも構築処理中の4 vCPUを確認し、再起動後は2 / 8 vCPUになった。
全VMで40 GiB・論理 / 物理セクター4096 B、SSH・sudo・cloud-init正常完了を確認した。

`parallel-check-app01`では再実行も行い、2 vCPU・32000 IOPSから4 vCPU・制限なしへ変更し、
成功後に2 vCPU・32000 IOPSへ戻ることを実機確認した。

子スクリプトを代替した検証では、4台のインストールとAnsible呼び出しがそれぞれ重なること、
VMごとの処理順序、指定した名前・CPU・メモリ・ISO・スイッチ・タイムアウトの引き継ぎを確認した。
1台に失敗を起こした場合も残り3台は完了し、全体の処理は失敗したVM名を報告して終了した。
資源設定の代替検証では、Ansible失敗時には最終設定を適用しないことと、再起動後のIP変更時の更新処理も確認した。

`parallel-check-app01`では4 vCPU・4 GiB・IOPS制限なしで、実際の公式`application.yml`も実行した。

```text
localhost : ok=124 changed=93 unreachable=0 failed=0 skipped=0 rescued=0 ignored=0
```

再起動後にDHCPのIPが変わり、SSH接続可能になった時点ではMySQLがまだ起動中だったため、
初回のDNS更新は接続エラーになった。MySQL・PowerDNSの起動完了を待つ処理を追加した。
導入済みのVMでゲストの構築処理を検証用に置き換え、修正後の資源切り替え・IP更新を再実行した。
最終的に2 vCPU・32000 IOPS、cloud-init正常完了、mysql・pdns・nginx・isupipe-goのactive、
`pipe.u.isucon.test`のDNS応答と環境変数が最終IPの`172.31.66.246`に一致すること、ホストからのHTTPS 200を確認した。
IP変更後も同じVMのSSHホスト鍵を確認できる設定を実機確認した。

4台すべての公式Ansibleを同時に最後まで実行する検証と、構築時間の比較は行っていない。
検証用VM4台とVHDX・関連ファイルは削除済み。既存の`uefi-test`は停止状態のまま保持した。

記録:

- `.local/results/parallel-orchestration-check.log`
- `.local/results/resource-lifecycle-check.log`
- `.local/results/parallel-hyperv-owners.json`
- `.local/results/parallel-hyperv-final.json`
- `.local/results/parallel-hyperv-guest-*.log`
- `.local/results/parallel-hyperv-retry-build-state.json`
- `.local/results/parallel-hyperv-retry.log`
- `.local/results/parallel-hyperv-application-build.log`
- `.local/results/parallel-hyperv-application-resource-retry.log`
- `.local/results/parallel-hyperv-application-check.log`
- `.local/results/parallel-hyperv-application-final.json`
- `.local/results/parallel-hyperv-cleanup.json`

### 4台構成とベンチ用VM（逐次構築時）

`New-Isucon13VM.ps1`の既定構成をアプリ3台＋ベンチ1台に変更した。
子スクリプトを検証用の代替に置き換え、次を確認した。

- 4台それぞれで、Ubuntuインストール後にAnsibleを呼び出す。
- アプリ3台は`application`、ベンチ1台は`benchmarker`を指定する。
- 既定値はアプリ各2 vCPU・4 GiB、ベンチ8 vCPU・8 GiB。指定した名前・資源・ISO・スイッチ・タイムアウトも引き継ぐ。
- 名前の重複・既存VM・アプリ台数の不一致は、VM作成前にエラーになる。
- 構築に失敗すると、後続VMの作成を中断する。

実機では`benchmark-role-check-01`を8 vCPU・8 GiBでISOから作成し、
`Invoke-Isucon13Ansible.ps1 -Role benchmarker`を実行した。
公式の`benchmark.yml`は終了コード0で完了した。

```text
localhost : ok=23 changed=19 unreachable=0 failed=0 skipped=0 rescued=0 ignored=0
```

`/home/isucon/bench_linux_amd64 run --help`の正常終了、既定ターゲットの`.test`ドメイン、
自己署名TLS用の設定を確認した。Nodeとアプリ用サービスは導入されていない。
4台すべての実機構築と、別VM間での負荷ベンチは今回実行していない。

検証用VMとディスクは削除済み。

記録:

- `.local/results/four-vm-orchestration-check.log`
- `.local/results/benchmark-vm-build.log`
- `.local/logs/ansible-benchmark-role-check-01-20260930-230851.log`
- `.local/results/benchmark-role-check.log`
- `.local/results/benchmark-vm-cleanup.json`

### Hyper-Vの停止・コンソール設定

変更後の`New-UbuntuVM.ps1`で、`vm-settings-check-01`へUbuntuをISOから無人インストールした。
VMはGeneration 2・2 vCPU・固定4 GiB。インストール後にHyper-Vコンソールを無効化し、
ディスクからの起動、SSH、passwordless sudo、cloud-init正常完了を確認した。
この検証時のディスク容量は64 GiB。現行の作成設定は40 GiBに変更している。

Hyper-V側でも次の設定を確認した。

- VSS連携: `Enabled=False`。
- 自動停止アクション: `ShutDown`。
- 仮想ディスプレイ・キーボード・マウス: なし。

ホストからの正常シャットダウンに成功した。検証用VMとディスクは削除済み。

記録:

- `.local/results/vm-settings-build.log`
- `.local/results/vm-settings-check.json`
- `.local/results/vm-settings-cleanup.json`

### ディスク容量・IOPS設定（2026-10-01）

[公式テンプレート](https://github.com/isucon/isucon13-portal/blob/master/isucon/portal/contest/templates/cloudformation_contest.yaml)は、
競技用3台をgp3・40 GiBで作成し、IOPSの追加指定は行っていない。
このため、制限値の基準には[gp3の標準3000 IOPS](https://docs.aws.amazon.com/ebs/latest/userguide/general-purpose.html)を使用した。

初回はアプリ3台へ`MaximumIOPS=3000`、ベンチ用へ`MaximumIOPS=0`を渡すことを、子スクリプトを代替した検証で確認した。
停止した一時VMに40 GiBのVHDXを接続し、Hyper-Vで3000と0を設定・読み取りできることも確認した。
`MinimumIOPS`はどちらも0だった。検証用VMとディスクは削除済み。

IOPSは[Hyper-Vの8 KiB換算](https://learn.microsoft.com/en-us/windows/win32/hyperv_v2/msvm-storageallocationsettingdata)で制限する。
16 KiBのI/Oは2回分として数えるため、3000の設定ではgp3より低い上限になる。
コミット`f6669a6`では、アプリ用を`MaximumIOPS=256000`へ変更した。
gp3標準の125 MiB/sと、[EBSによる小さなI/Oの結合](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-io-characteristics.html)を考慮し、
最小512 BのI/Oまで許容する保守的な上限として`125 MiB/s ÷ 512 B = 256000`を採用した。
512 Bの倍数の読み書きでは、8 KiB換算カウントは転送量を512 Bで割った値を超えないため、
125 MiB/s以下の読み書きをこの上限のために制限することはない。

この時のアプリ3台へ256000、ベンチ用へ0を渡すことを、子スクリプトを代替した検証で再確認した。
上限の計算とPowerShellの構文も確認した。
256000の実機設定確認とI/O負荷をかけた速度測定は行っていない。実性能はホストのストレージや同時負荷に依存する。

記録:

- `.local/results/four-vm-iops-check.log`
- `.local/results/storage-qos-check.json`
- `.local/results/storage-qos-cleanup.json`
- `.local/results/four-vm-gp3-limit-check.log`
- `.local/results/gp3-limit-calculation-check.log`

### 4KnとIOPS上限（2026-10-01）

現行構成では全VMのVHDXを4Kn（論理・物理セクター各4096 B）に変更し、
アプリ用の上限を`MaximumIOPS=32000`、ベンチ用を0とした。
VHDXの作成時に`LogicalSectorSizeBytes`と`PhysicalSectorSizeBytes`を両方4096に指定する。

4 KiBの倍数のデータI/Oについて、サイズが`4 KiB × n`なら、Hyper-Vの換算数は`ceil(n / 2) ≤ n`となる。
したがって、要求ごとの切り上げとサイズの混在を含めても、総換算数は総転送量を4 KiBで割った値を超えない。
EBS側での結合も考慮した保守的な上限として、`125 MiB/s ÷ 4 KiB = 32000`を使用する。
上限の計算、PowerShellの構文、アプリ3台へ32000・ベンチ用へ0を渡すことを確認した。

変更後の`New-UbuntuVM.ps1`で、`fourkn-install-check-01`をISOから作成し、次を実機で確認した。

- Ubuntu Server 22.04.5の無人インストール、ISO解除、ディスクからの起動、SSH、passwordless sudo、cloud-init正常完了。
- Hyper-V側: 40 GiB、論理・物理セクター4096 B、`MaximumIOPS=32000`、`MinimumIOPS=0`。
- ゲスト側: `/dev/sda`の論理・物理セクター4096 B、ルートファイルシステムはext4。
- 4 KiB・16 KiB単位のDirect I/Oによるファイル読み書き。
- MySQL `8.0.46-0ubuntu0.22.04.4`を`innodb_flush_method=O_DIRECT`で起動。ページサイズは16384 B。
- InnoDBへ1000行・計1024000 Bのペイロードを書き込み、`CHECK TABLE`がOK。MySQLサービス停止・再起動後も行数とデータ量が一致。

今回の実機確認はUbuntuとMySQLに限定し、公式Ansible全体と負荷ベンチは再実行していない。
検証用VMとVHDXを含む専用ディレクトリは削除済み。検証前から存在したVMは変更していない。

記録:

- `.local/results/four-vm-4kn-limit-check.log`
- `.local/results/4kn-limit-calculation-check.log`
- `.local/results/fourkn-vm-build.log`
- `.local/results/fourkn-host-check.json`
- `.local/results/fourkn-guest-check.log`
- `.local/results/fourkn-vm-cleanup.json`

## 旧構成の検証記録

以下はコミット`817cafd`までの旧構成の検証記録。

### 条件

以下は初回検証時の構成。autoinstall変更後の確認は後述する。

| 項目 | 使用した構成 |
| --- | --- |
| ホスト | Windows 11 Pro＋Hyper-V、PowerShell 7.6.6 |
| ISO | `D:\iso\ubuntu-22.04.5-live-server-amd64.iso` |
| 仮想スイッチ | `Default Switch` |
| golden作成用VM | Generation 2、2 vCPU、固定4 GiB、64 GiB dynamic VHDX、Secure Boot無効 |
| ubuntu-clone01 | 8 vCPU、固定8 GiB。公式Ansible実行先 |
| ubuntu-clone02 | 2 vCPU、固定4 GiB。素Ubuntuでcloneの独立性を確認 |
| ISUCON13 commit | `8f6afdc3603f0c661368de4659a7240862f59623` |

各VMのディスクは、golden VHDXをフルコピーして作成した。
インストーラーの手動操作も行っていない。

### golden作成

`Build-GoldenImage.ps1`を最初から実行し、終了コード0で完了した。

| 確認 | 結果 |
| --- | --- |
| NoCloud CD生成・GRUBへのautoinstall起動入力 | スクリプトで完了 |
| Ubuntu Server 22.04のインストール | 無人で完了・poweroff |
| DVDのISO解除・ディスクから起動 | スクリプトで完了 |
| 管理ユーザー`ubuntu`・公開鍵SSH・passwordless sudo | 成功 |
| UEFI起動・SSHサービス | 確認済み |
| cloud-init | `status: done`、errorsなし |
| ssh_deletekeys | `true` |
| generalize | `99-installer.cfg`除去、`cloud-init clean --logs --machine-id`完了 |
| shutdown・作成用VM登録解除 | 完了 |
| 成果物 | VHDX・Dynamic、Attached=False |

成果物は`golden/ubuntu-server-22.04/disk.vhdx`。
ISUCON13・Ansibleは含まない。初回検証のgoldenから起動したcloneでも未導入を確認した。

初回検証のgoldenのSHA-256（clone作成前後で一致）:

```text
4CF62E21CB9BF1B0055A035BF04D829EDA8487D47EBB02FC7601CC54FC185AB6
```

ログ: `.local/results/golden-build-final.log`

### cloneの独立性

`New-UbuntuVM.ps1`によるフルコピーと`Test-UbuntuClones.ps1`による検証に成功した。
両VMのNoCloud instance-idは各seedの指定値と一致し、cloud-initはerrorsなしで完了した。
SSH・sudo・UEFI起動も確認した。

| VM | machine-id |
| --- | --- |
| ubuntu-clone01 | `8eaefa9dfa4b4910adbd374e19eec26e` |
| ubuntu-clone02 | `21c2dae62bc44bc093d15e6d5cd17669` |

VM ID・MAC・SSH host key・instance-idもすべて異なった。
両VMの自動checkpointは無効。
goldenの再ビルド後、ubuntu-clone02はそのgoldenから作り直して検証した。

記録: `.local/results/clone-verification.json`

### cloneへの公式Ansible

`Invoke-Isucon13Ansible.ps1 -VMName ubuntu-clone01`で完了した。
公式の`make_latest_files.sh`と`application.yml`を使用した。
clone内のソース・設定のドメインを`.test`に置換し、自己署名証明書を生成して再実行した。
ベンチのTLS検証はvagrant-isucon／wsl-isuconと同様に省略する設定へ変更した。

```text
localhost : ok=124 changed=36 unreachable=0 failed=0 skipped=0 rescued=0 ignored=0
```

| 確認 | 結果 |
| --- | --- |
| ubuntu・isucon・isuadmin | 作成済み、各ユーザーの役割を分離 |
| mysql・pdns・nginx・isupipe-go | すべてactive |
| フロントエンド | ゲスト内・Windowsホストから証明書検証付きHTTPSでHTTP 200 |
| `POST /api/initialize` | 成功、`{"language":"golang"}` |
| PowerDNSの`pipe.u.isucon.test` Aレコード | `172.31.71.231`（clone01のIPv4） |
| `ISUCON13_POWERDNS_SUBDOMAIN_ADDRESS` | clone01のIPv4 |

ログ:

- `.local/logs/ansible-ubuntu-clone01-20260930-092858.log`
- `.local/results/test-domain-check.log`
- `.local/results/host-test-domain-check.log`

### .test・自己署名TLS

使用するドメインは`*.u.isucon.test`・`*.t.isucon.test`。
両方についてRSA 2048 bit、SAN付きの自己署名証明書を生成した。
SubjectとIssuerが一致し、期限は2036-09-27 00:29:01 UTC。

ゲスト内とWindowsホストのHTTPS確認では、生成した公開証明書を`curl --cacert`に渡した。
証明書検証を省略せず、両方でHTTP 200になった。

公式ベンチを`--nameserver 172.31.71.231 --enable-ssl --pretest-only`で実行し、
静的ファイル・初期化・データ整合性チェックに成功した。
`--pretest-only`は整合性確認の後に終了するため、結果JSONは作成しない。
通常の負荷ベンチも60秒の走行と最終チェックまで完了し、終了コード0になった。

| 項目 | 結果 |
| --- | --- |
| pass | `true` |
| score | `16845` |
| language | `golang` |
| resolved_count | `47901` |
| 名前解決失敗 | `0` |

結果のmessagesには一部のHTTP 404・500を報告する一般エラーも含まれるが、最終判定は`pass: true`。
アプリとベンチは同じ8 vCPU・8 GiBのVMで実行した。スコアはこの構成の動作確認値。

ログ: `.local/results/test-domain-benchmark.log`
結果: `.local/results/test-domain-benchmark.json`

実装参照:

- [vagrant-isucon](https://github.com/matsuu/vagrant-isucon/blob/master/isucon13-standalone/Vagrantfile)
- [wsl-isucon](https://github.com/matsuu/wsl-isucon/blob/main/isucon13/scripts/01-provisioning.sh)

### autoinstall変更後の再検証

同じISOを使い、変更後の`Build-GoldenImage.ps1`を最初から実行した。
無人インストール・起動確認・generalize・停止・golden保存まで終了コード0で完了した。

| 確認 | 結果 |
| --- | --- |
| インストール元 | `ubuntu-server-minimal` |
| 管理ユーザー | `user-data`の`users: [default]`で`ubuntu`を作成。公開鍵SSH・passwordless sudo成功 |
| ディスク構成 | `direct`。EFI領域とext4領域を確認、LVMなし |
| SSHパスワード認証 | 無効。`sshd -T`で`passwordauthentication no`を確認 |
| ホスト名 | `autoinstall-check-01`・`autoinstall-check-02`、各seedの指定値と一致 |
| cloud-init・cloneの独立性 | 2台とも正常完了。VM ID・MAC・machine-id・SSH host key・instance-idの重複なし |
| NoCloud CD生成 | Windows標準のIMAPIで生成し、インストールとclone起動で使用できた |

minimalにはIPv4通知用の`hv-kvp-daemon`が含まれなかったため、
`linux-cloud-tools-virtual`を追加し、ホストからのIPv4取得を確認した。

2 vCPU・4 GiBの`autoinstall-check-01`で、公式Ansibleも再検証した。
最初の実行ではNode 20.10.0のnpmが`io_uring`内で停止した。
カーネルの待機スタックを記録し、VMを再起動した。
構築処理に`UV_USE_IO_URING=0`を設定し、Ansibleのsudo先にも引き継いで再実行した。
この変数による無効化は[libuv 1.46の実装](https://github.com/libuv/libuv/blob/v1.46.0/src/unix/linux.c#L395)で確認できる。

修正後の`Invoke-Isucon13Ansible.ps1`は終了コード0で完了した。

```text
localhost : ok=124 changed=38 unreachable=0 failed=0 skipped=0 rescued=0 ignored=0
```

mysql・pdns・nginx・isupipe-goのactive、証明書検証付きHTTPSのHTTP 200、
初期化APIの`{"language":"golang"}`、DNSの`172.31.79.15`応答を確認した。
今回の構成では負荷ベンチは再実行していない。上記のスコアは初回検証時の記録。

記録:

- `.local/results/autoinstall-minimal-verified-build.log`
- `.local/results/autoinstall-minimal-clone-verification.json`
- `.local/results/autoinstall-minimal-npm-kernel.log`
- `.local/logs/ansible-autoinstall-check-01-20260930-212219.log`
- `.local/results/autoinstall-minimal-application.log`
- `.local/results/autoinstall-minimal-cleanup.json`

### 検証後の削除

2026-09-30に、検証用VMの`ubuntu-clone01`・`ubuntu-clone02`を停止し、VM登録と関連ファイルを削除した。
golden VHDXも削除済み。スクリプトと検証ログは残している。

再検証の`autoinstall-check-01`・`autoinstall-check-02`、作成したgolden VHDXと関連ファイルも削除した。
Hyper-Vに残っているのは、今回の検証対象ではない`uefi-test`（停止中）のみ。

### 残る事項

- 自己署名証明書をブラウザで使うには、証明書を信頼するか警告を許可する必要がある。
- Hyper-VではAWSのpublic IP取得処理が働かない。現在はAnsible実行時のclone IPv4が設定される。DHCPでIPが変わった場合の更新方法は未実装。
