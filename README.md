# Hyper-V ISUCON13 検証環境

Packerは使用しない。素のUbuntu Serverをgolden VHDXにし、フルコピーしたcloneへ公式Ansibleを実行する。

```text
golden作成用VM・NoCloud CDを準備 → ISOからUbuntu Serverをautoinstall
→ cloud-init・SSH・sudoを確認 → generalize・shutdown
→ golden VHDXをフルコピーして新規VM作成
→ cloneのcloud-init完了 → .testドメイン・自己署名証明書を準備 → 公式ISUCON13 Ansible
```

## スクリプト

| スクリプト | 処理 |
| --- | --- |
| `Build-GoldenImage.ps1` | 無人インストールからgeneralize・golden VHDX保存までの一括実行 |
| `New-GoldenVM.ps1` | 独立VHDX、Generation 2 VM、ISO・NoCloud CD接続、autoinstall起動 |
| `Complete-GoldenImage.ps1` | cloud-initのgeneralize、shutdown、golden VHDX保存、作成用VMの登録解除 |
| `New-UbuntuVM.ps1` | goldenのフルコピー、新規VM、VMごとのNoCloud CDの作成 |
| `Invoke-Isucon13Ansible.ps1` | clone内で公式ソース取得、.test・自己署名証明書の設定、成果物生成、公式Ansible実行 |
| `Test-UbuntuClones.ps1` | cloud-init・SSH・sudo・clone間のIDの独立性を確認 |

PowerShellスクリプトは`scripts/`、ゲストで使うシェルスクリプトは`scripts/guest/`にある。

## ホストの前提

- Windows＋Hyper-V、PowerShell 7.3以上、Windows OpenSSH Client。
- 管理者またはHyper-V Administratorsグループの権限。
- DHCP、外部への通信、ホストからのSSHが使える仮想スイッチ。既定は`Default Switch`。
- autoinstall・cloneのNoCloud CD生成用にWindows ADK Deployment Toolsの`oscdimg.exe`。
- Ubuntu Server 22.04 amd64のインストーラーISO。

## 1. 素のUbuntu goldenを作る

リポジトリルートで実行する。

```powershell
.\scripts\Build-GoldenImage.ps1
```

既定のISOは`D:\iso\ubuntu-22.04.5-live-server-amd64.iso`。
別の場所のISOは`-IsoPath`で指定できる。
Generation 2、2 vCPU、固定メモリ4 GiB、Secure Boot無効、独立した64 GiBのdynamic VHDXを作成する。
既存の同名VM・ディスクは上書きしない。

NoCloud CDを`oscdimg`で自動生成し、Hyper-Vの仮想キーボードAPIでGRUBへautoinstall起動コマンドを送る。
インストーラー操作は不要。管理ユーザー`ubuntu`、公開鍵SSH、passwordless sudo、IP通知用の
`linux-cloud-tools-virtual`をインストール時に設定する。
インストール完了後にpoweroffし、スクリプトがDVDのISOを解除してディスクから起動する。
IPv4とSSH接続を待ち、cloud-init・OS・sudo・UEFI・`ssh_deletekeys`を確認してgeneralizeする。

GeneralizeではServerインストーラーの`99-installer.cfg`を除去した後、
標準の`cloud-init clean --logs --machine-id`と`poweroff`を実行する。
これによりcloneは自身のNoCloud設定を検出し、machine-idとSSH host keyを再生成する。

完成するgolden原本:

```text
golden/ubuntu-server-22.04/disk.vhdx
```

goldenへISUCON13やAnsibleは導入しない。原本は直接起動せず保存する。

## 2. フルコピーしてcloneを作る

```powershell
$golden = (Resolve-Path '.\golden\ubuntu-server-22.04\disk.vhdx').Path
.\scripts\New-UbuntuVM.ps1 -Name ubuntu-clone01 -GoldenVhdxPath $golden -Start
.\scripts\New-UbuntuVM.ps1 -Name ubuntu-clone02 -GoldenVhdxPath $golden -Start
.\scripts\Test-UbuntuClones.ps1
```

ディスクは`Copy-Item`でフルコピーする。differencing VHDXは使わない。
VM・NIC・MACは新規作成し、NoCloudのinstance-idもVMごとに生成する。
NoCloud CDはそのVMへ付けたままにする。
管理ユーザー`ubuntu`は残し、cloneの初回起動時にSSH公開鍵を設定する。

cloneのファイルは`vm/<VM名>/`、SSH鍵・検証結果は`.local/`に保存する。

## 3. cloneへ公式Ansibleを実行する

```powershell
.\scripts\Invoke-Isucon13Ansible.ps1 -VMName ubuntu-clone01
.\scripts\Invoke-Isucon13Ansible.ps1 -VMName ubuntu-clone02
```

スクリプトはclone内で次の順に実行する。

1. cloud-init完了確認。
2. Ansible等を導入し、公式が使うxbuildで成果物生成用のGo・Nodeを準備。
3. GitHubの`isucon/isucon13`を取得。
4. ソース・nginx設定・DNS zone・Cookie等の`isucon.dev`を`isucon.test`へ置換。
5. `*.u.isucon.test`・`*.t.isucon.test`の自己署名証明書を生成。DNS zoneファイル名も変更。
6. 参照実装と同様に、生成するベンチマーカーのTLS証明書検証を省略する設定へ変更。
7. 公式`provisioning/ansible/make_latest_files.sh`を実行。
8. 公式inventoryの`application`へ`application.yml`を実行。

公式Ansibleを基本に、clone内のチェックアウトへドメイン・TLSの変更を適用する。
証明書はRSA 2048 bit、SAN付き、有効期間3650日で、構築スクリプトの実行ごとに生成する。
再実行すると公式AnsibleのDB初期化も再実行される。

AWS用IP設定サービスはHyper-VでAWSのIP取得を行わないため、公式Ansibleが設定するcloneのIPv4を使用する。
DHCPでIPが変わった場合の更新方法は未実装。

参考: [公式ISUCON13](https://github.com/isucon/isucon13)、
[vagrant-isuconのVagrantfile](https://github.com/matsuu/vagrant-isucon/blob/master/isucon13-standalone/Vagrantfile)、
[wsl-isuconの構築スクリプト](https://github.com/matsuu/wsl-isucon/blob/main/isucon13/scripts/01-provisioning.sh)。
参照先はGitHub上の現行内容を使用した。参照先の`.local`に相当するドメインには`.test`を採用している。

## 4. HTTPS・ベンチマーク

サイトのURLは`https://pipe.u.isucon.test/`。
Windowsのブラウザで開く場合は、hostsに`<cloneのIPv4> pipe.u.isucon.test`を追加する。
自己署名証明書なので、ブラウザで証明書を信頼するか警告を許可する。

hostsを変更せずに応答を確認する例:

```powershell
curl.exe --noproxy '*' --insecure --resolve pipe.u.isucon.test:443:<cloneのIPv4> https://pipe.u.isucon.test/
```

ベンチは構築済みcloneへ`ubuntu`でSSH接続して実行する。
公式の成果物生成で作られたバイナリを使う。

```bash
cd /home/ubuntu/isucon13/bench
../provisioning/ansible/roles/bench/files/bench_linux_amd64 run \
  --nameserver <cloneのIPv4> --enable-ssl
```

初期化・整合性確認のみ行う場合は`--pretest-only`を追加する。
通常の負荷ベンチの結果は`/tmp/result.json`に保存される。`--pretest-only`では結果JSONを作成しない。
同じVM上でアプリとベンチを動かすため、スコアにはベンチ自身の負荷も含まれる。

## 確認状況

2026-09-30にWindows＋Hyper-Vの実機で確認した。

- `Build-GoldenImage.ps1`が手動操作なしで完了し、停止・generalize済みの独立VHDXを保存。
- 2台のcloneでcloud-init・SSH・sudoを確認。VM ID・MAC・machine-id・SSH host key・instance-idはすべて独立。
- フルコピー後もgolden原本のSHA-256は不変。
- clone 1台へ公式Ansibleを実行し、`failed=0`で完了。
- MySQL・PowerDNS・nginx・Go版webappが起動。WindowsホストからHTTP 200、初期化API・DNSも確認。

- `.test`・自己署名証明書を適用して公式Ansibleを再実行し、`failed=0`で完了。
- ゲスト内・Windowsホストとも、生成した証明書を`curl --cacert`へ渡す証明書検証付きHTTPSでHTTP 200。
- `pipe.u.isucon.test`のDNS応答と初期化APIを確認。
- `--enable-ssl`でpretest・通常の負荷ベンチを完了。`pass: true`、スコア16845。

条件・ログ・残る事項は[検証記録](docs/validation.md)を参照。
