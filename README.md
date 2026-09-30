# Hyper-V ISUCON13 検証環境

Ubuntu Server ISOからVMを作成し、ISUCON13を構築する。
使用するドメインは`*.u.isucon.test`・`*.t.isucon.test`、TLS証明書は自己署名証明書。

## ユーザーが行う操作

### 事前準備

次を用意する。

- Windows＋Hyper-V、PowerShell 7.3以上、Windows OpenSSH Client。
- 管理者またはHyper-V Administratorsグループの権限。
- Ubuntu Server 22.04 amd64のインストーラーISO。

以下の構築コマンドは、WindowsのPowerShellでリポジトリのルートディレクトリから実行する。

### VMを構築する

新規作成するVM名と、使用するISOを指定して実行する。
`-Name`と`-IsoPath`は必須。VM名には未使用の名前を選ぶ。

```powershell
$vmName = 'isucon13-vm01'
.\scripts\New-Isucon13VM.ps1 -Name $vmName -IsoPath 'D:\iso\ubuntu-22.04.5-live-server-amd64.iso'
```

ISOが別の場所にある場合は、`-IsoPath`の値を変更する。
仮想スイッチを変更する場合は、`-SwitchName 'スイッチ名'`を追加する。省略時は`Default Switch`を使用する。

このコマンドが正常終了すれば、構築は完了。
VMを増やす場合は、VM名を変えて同じコマンドを実行する。

### Ansibleで失敗した場合の再実行

Ubuntuのインストールが完了し、Ansibleで失敗した場合は、対象VMを起動した状態で次を実行する。
再実行するとDBは初期化される。

```powershell
.\scripts\Invoke-Isucon13Ansible.ps1 -VMName $vmName
```

### 任意: HTTPS応答を確認する

対象VMのIPアドレスを確認する。

```powershell
(Get-VMNetworkAdapter -VMName $vmName).IPAddresses
```

以下の`<VMのIPv4>`を、確認したIPv4アドレスに置き換えて実行する。
自己署名証明書を使うため、この確認コマンドでは証明書検証を省略する。

```powershell
curl.exe --noproxy '*' --insecure --resolve pipe.u.isucon.test:443:<VMのIPv4> https://pipe.u.isucon.test/
```

ブラウザで閲覧する場合は、管理者権限でWindowsの`C:\Windows\System32\drivers\etc\hosts`へ次の行を追加する。

```text
<VMのIPv4> pipe.u.isucon.test
```

`https://pipe.u.isucon.test/`を開き、証明書を信頼させるか、ブラウザの警告画面からアクセスを続行する。

### 任意: ベンチを実行する

WindowsのPowerShellから対象VMへSSHログインする。`<VMのIPv4>`は実際のIPv4アドレスに置き換える。

```powershell
ssh -i .local\ssh\id_ed25519 ubuntu@<VMのIPv4>
```

ログイン後のUbuntuシェルで、次のコマンドを実行する。
`--nameserver`には対象VMのIPv4アドレスを指定する。

```bash
cd /home/ubuntu/isucon13/bench
../provisioning/ansible/roles/bench/files/bench_linux_amd64 run \
  --nameserver <VMのIPv4> --enable-ssl
```

初期化・整合性確認のみ行う場合は`--pretest-only`を追加する。
通常の負荷ベンチの結果はVM内の`/tmp/result.json`で確認できる。

## スクリプトが自動で行う処理

| スクリプト | 自動で行う処理 |
| --- | --- |
| `New-Isucon13VM.ps1` | VM作成からUbuntuのインストール、ISUCON13の構築までを順に実行 |
| `New-UbuntuVM.ps1` | 新規VMの作成、Ubuntuの無人インストール、SSH・sudo・cloud-initの確認 |
| `Invoke-Isucon13Ansible.ps1` | 必要なソフトウェアと公式ソースの取得、.test・自己署名証明書の設定、ビルド、公式Ansibleによるサービスの設定・起動 |

`New-Isucon13VM.ps1`は、`New-UbuntuVM.ps1`の完了後に`Invoke-Isucon13Ansible.ps1`を呼び出す。
`Invoke-Isucon13Ansible.ps1`は、Ubuntu内で`scripts/guest/provision-isucon13.sh`を実行する。

### 生成物と既定の設定

| 生成物 | 保存先 |
| --- | --- |
| VMのディスク・設定 | `vm/<VM名>/` |
| SSH鍵・ログ・検証結果 | `.local/` |

- 作成するVMの既定値はGeneration 2、2 vCPU、固定メモリ4 GiB、64 GiBのVHDX、Secure Boot無効。
- 管理ユーザーは`ubuntu`。公開鍵SSHとパスワード不要のsudoを設定する。
- ベンチは自己署名証明書を使えるよう、TLS証明書検証を省略する設定にする。
- 同名のVMや作成先のディスクが既にある場合は、上書きせずエラーで終了する。
- `Invoke-Isucon13Ansible.ps1`の再実行時には、証明書の再生成とDBの初期化も行う。

### 動作上の制約

- DNSにはAnsible実行時のVMのIPv4アドレスを設定する。DHCPでIPが変わった際の設定自動更新は未実装。
- `--pretest-only`ではベンチ結果のJSONを作成しない。
- 上記のベンチ実行方法では、アプリとベンチが同じVMのCPU・メモリを使うため、ベンチ自身の負荷もスコアに影響する。

## 検証記録・参考

検証条件と結果は[検証記録](docs/validation.md)を参照。

- [公式ISUCON13](https://github.com/isucon/isucon13)
- [vagrant-isuconのVagrantfile](https://github.com/matsuu/vagrant-isucon/blob/master/isucon13-standalone/Vagrantfile)
- [wsl-isuconの構築スクリプト](https://github.com/matsuu/wsl-isucon/blob/main/isucon13/scripts/01-provisioning.sh)
