# Hyper-V ISUCON13 検証環境

Ubuntu Server ISOからアプリ用3台・ベンチ用1台のVMを作成し、ISUCON13を構築する。
使用するドメインは`*.u.isucon.test`・`*.t.isucon.test`、TLS証明書は自己署名証明書。

## ユーザーが行う操作

### 事前準備

次を用意する。

- Windows＋Hyper-V、PowerShell 7.3以上、Windows OpenSSH Client。
- 管理者またはHyper-V Administratorsグループの権限。
- Ubuntu Server 22.04 amd64のインストーラーISO。

以下の構築コマンドは、WindowsのPowerShellでリポジトリのルートディレクトリから実行する。

### VMを構築する

使用するISOを指定して実行する。

```powershell
.\scripts\New-Isucon13VM.ps1 -IsoPath 'D:\iso\ubuntu-22.04.5-live-server-amd64.iso'
```

ISOが別の場所にある場合は、`-IsoPath`の値を変更する。
仮想スイッチを変更する場合は、`-SwitchName 'スイッチ名'`を追加する。省略時は`Default Switch`を使用する。

既定のVM名は、アプリ用が`isucon13-app01`・`isucon13-app02`・`isucon13-app03`、ベンチ用が`isucon13-bench`。
名前を変更する場合は、`-ApplicationName 'app01','app02','app03' -BenchmarkerName 'bench'`を追加する。
VM名には未使用の名前を選ぶ。このコマンドが正常終了すれば、4台の構築は完了。

### Ansibleで失敗した場合の再実行

Ubuntuのインストールが完了し、Ansibleで失敗した場合は、失敗したVM名を`$vmName`に指定し、VMを起動した状態で次を実行する。
アプリ用VMでは、再実行するとDBは初期化される。

```powershell
$vmName = 'isucon13-app02'
.\scripts\Invoke-Isucon13Ansible.ps1 -VMName $vmName
```

ベンチ用VMの場合は、次を実行する。

```powershell
.\scripts\Invoke-Isucon13Ansible.ps1 -VMName 'isucon13-bench' -Role benchmarker
```

未作成のVMが残った場合は、VM名とISOのパスを指定してUbuntuをインストールする。

```powershell
.\scripts\New-UbuntuVM.ps1 -Name '<VM名>' -IsoPath '<ISOのパス>'
```

ベンチ用VMの作成には`-MemoryStartupBytes 8GB -ProcessorCount 8 -MaximumIOPS 0`を追加する。
Ubuntuのインストール後、上記の役割に応じたAnsibleコマンドを実行する。

### 任意: HTTPS応答を確認する

確認するVM名を`$vmName`に指定し、IPアドレスを確認する。

```powershell
$vmName = 'isucon13-app01'
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

WindowsのPowerShellで、対象アプリとベンチ用VMのIPv4アドレスを確認する。

```powershell
(Get-VMNetworkAdapter -VMName 'isucon13-app01').IPAddresses
(Get-VMNetworkAdapter -VMName 'isucon13-bench').IPAddresses
```

ベンチ用VMへSSHログインする。`<ベンチVMのIPv4>`は確認したIPv4アドレスに置き換える。

```powershell
ssh -i .local\ssh\id_ed25519 ubuntu@<ベンチVMのIPv4>
```

ログイン後のUbuntuシェルで、次のコマンドを実行する。
`--nameserver`には対象アプリVMのIPv4アドレスを指定する。

```bash
cd /home/ubuntu/isucon13/bench
/home/isucon/bench_linux_amd64 run \
  --nameserver <アプリVMのIPv4> --enable-ssl
```

初期化・整合性確認のみ行う場合は`--pretest-only`を追加する。
通常の負荷ベンチの結果はVM内の`/tmp/result.json`で確認できる。

## スクリプトが自動で行う処理

| スクリプト | 自動で行う処理 |
| --- | --- |
| `New-Isucon13VM.ps1` | アプリ用3台・ベンチ用1台について、VM作成からUbuntuのインストール、各役割のISUCON13構築までを順に実行 |
| `New-UbuntuVM.ps1` | 新規VMの作成、Ubuntuの無人インストール、SSH・sudo・cloud-initの確認 |
| `Invoke-Isucon13Ansible.ps1` | 必要なソフトウェアと公式ソースの取得、.testへの変更、各役割に必要なビルドと公式Ansibleの実行。アプリ用VMでは証明書を生成し、サービスを設定・起動 |

`New-Isucon13VM.ps1`は、`New-UbuntuVM.ps1`の完了後に`Invoke-Isucon13Ansible.ps1`を呼び出す。
`Invoke-Isucon13Ansible.ps1`は、Ubuntu内で`scripts/guest/provision-isucon13.sh`を実行する。
公式Ansibleは、アプリ用VMには`application.yml`、ベンチ用VMには`benchmark.yml`を使用する。

### 生成物と既定の設定

| 生成物 | 保存先 |
| --- | --- |
| VMのディスク・設定 | `vm/<VM名>/` |
| SSH鍵・ログ・検証結果 | `.local/` |

- アプリ用VMの既定値は各2 vCPU・固定メモリ4 GiB、ベンチ用VMは8 vCPU・固定メモリ8 GiB。
- 全VMでGeneration 2、40 GiBの4Kn VHDX（論理・物理セクター各4 KiB）、Secure Boot無効を使用する。
- アプリ用VMのディスクは最大32000 IOPS（Hyper-Vの8 KiB換算）。ベンチ用VMはIOPS制限なし。
- ボリュームシャドウコピー（VSS）とHyper-Vコンソールは無効。自動開始アクションはなし、自動停止アクションはシャットダウン。
- 管理ユーザーは`ubuntu`。公開鍵SSHとパスワード不要のsudoを設定する。
- ベンチは自己署名証明書を使えるよう、TLS証明書検証を省略する設定にする。
- 同名のVMや作成先のディスクが既にある場合は、上書きせずエラーで終了する。
- 構築中にエラーが発生すると処理を中断する。
- アプリ用VMで`Invoke-Isucon13Ansible.ps1`を再実行すると、証明書の再生成とDBの初期化も行う。

### 動作上の制約

- IOPS上限は、[gp3標準の3000 IOPS・125 MiB/s](https://docs.aws.amazon.com/ebs/latest/userguide/general-purpose.html)をこの制限によって下回らせないための保守的な値。[EBSが小さなI/Oを結合する場合](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-io-characteristics.html)も考慮し、4Knの最小I/Oを基準に`125 MiB/s ÷ 4 KiB = 32000`を採用している。データの読み書きでは、要求ごとの8 KiB換算の切り上げを含めても、換算数は転送量を4 KiBで割った値を超えない。
- 実性能はホストのストレージや同時負荷に依存する。gp3と同じ性能を再現する設定ではない。
- DNSにはAnsible実行時のVMのIPv4アドレスを設定する。DHCPでIPが変わった際の設定自動更新は未実装。
- `--pretest-only`ではベンチ結果のJSONを作成しない。

## 検証記録・参考

検証条件と結果は[検証記録](docs/validation.md)を参照。

- [公式ISUCON13](https://github.com/isucon/isucon13)
- [vagrant-isuconのVagrantfile](https://github.com/matsuu/vagrant-isucon/blob/master/isucon13-standalone/Vagrantfile)
- [wsl-isuconの構築スクリプト](https://github.com/matsuu/wsl-isucon/blob/main/isucon13/scripts/01-provisioning.sh)
