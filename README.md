# Hyper-V ISUCON13 検証環境

Ubuntu Server ISOからアプリ用3台・ベンチ用1台のVMを作成し、ISUCON13を構築する。
使用するドメインは`*.u.isucon.test`・`*.t.isucon.test`、TLS証明書は自己署名証明書。

## ユーザーが行う操作

### 事前準備

次を用意する。

- Windows＋Hyper-V、PowerShell 7.3以上、Windows OpenSSH Client。
- WSLCを利用できるWSL 2.9.3以上（`wslc version`で確認）。
- 管理者またはHyper-V Administratorsグループの権限。
- Ubuntu Server 22.04 amd64のインストーラーISO。

以下の構築コマンドは、WindowsのPowerShellでリポジトリのルートディレクトリから実行する。

### VMを構築する

使用するISOと保存先フォルダーを指定して実行する。

```powershell
$outputPath = 'D:\isucon13'
.\scripts\New-Isucon13VM.ps1 -IsoPath 'D:\iso\ubuntu-22.04.5-live-server-amd64.iso' -OutputPath $outputPath
```

ISOが別の場所にある場合は、`-IsoPath`の値を変更する。
保存先を変更する場合は、`$outputPath`の値を変更する。`-OutputPath`は必須で、フォルダーは事前に作成しなくてよい。
仮想スイッチを変更する場合は、`-SwitchName 'スイッチ名'`を追加する。省略時は`Default Switch`を使用する。

既定のVM名は、アプリ用が`isucon13-app01`・`isucon13-app02`・`isucon13-app03`、ベンチ用が`isucon13-bench`。
名前を変更する場合は、`-ApplicationName 'app01','app02','app03' -BenchmarkerName 'bench'`を追加する。
構築後のCPU数を変更する場合は、`-ProcessorCount <アプリ用CPU数> -BenchmarkerProcessorCount <ベンチ用CPU数>`を追加する。
VM名には未使用の名前を選ぶ。このコマンドが正常終了すれば、4台の構築は完了。

### VMへSSH接続する

WindowsのPowerShellで、構築時の保存先を`$outputPath`、接続したいVM名を`$vmName`に指定して実行する。
アプリ用・ベンチ用とも、保存先の`ssh/id_ed25519`を使い、`ubuntu`ユーザーとしてログインする。

```powershell
$outputPath = 'D:\isucon13'
$vmName = 'isucon13-app01'
$vmIP = (Get-VMNetworkAdapter -VMName $vmName).IPAddresses |
    Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } |
    Select-Object -First 1
$knownHosts = Join-Path $outputPath "ssh\known_hosts_$vmName"
ssh -i (Join-Path $outputPath 'ssh\id_ed25519') `
    -o "HostKeyAlias=$vmName" `
    -o "UserKnownHostsFile=`"$knownHosts`"" `
    "ubuntu@$vmIP"
```

他のVMへ接続する場合は、`$vmName`を`isucon13-app02`・`isucon13-app03`・`isucon13-bench`などのVM名に変更する。
アプリ用VMで`isucon`ユーザーとして作業する場合は、ログイン後に`sudo -iu isucon`を実行する。

### Ansibleで失敗した場合の再実行

Ubuntuのインストールが完了し、Ansibleで失敗した場合は、構築時の保存先を`$outputPath`、失敗したVM名を`$vmName`に指定し、VMを起動した状態で次を実行する。
アプリ用VMでは、再実行するとDBは初期化される。

```powershell
$outputPath = 'D:\isucon13'
$vmName = 'isucon13-app02'
.\scripts\Invoke-Isucon13Ansible.ps1 -VMName $vmName -OutputPath $outputPath
```

ベンチ用VMの場合は、次を実行する。

```powershell
.\scripts\Invoke-Isucon13Ansible.ps1 -VMName 'isucon13-bench' -OutputPath $outputPath -Role benchmarker
```

CPU数を変更していた場合は、再実行にも`-ProcessorCount <構築後のCPU数>`を指定する。

未作成のVMが残った場合は、VM名とISOのパスを指定してUbuntuをインストールする。

```powershell
.\scripts\New-UbuntuVM.ps1 -Name '<VM名>' -IsoPath '<ISOのパス>' -OutputPath $outputPath
```

ベンチ用VMの作成には`-MemoryMaximumBytes 8GB`を追加する。
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

「[VMへSSH接続する](#vmへssh接続する)」の手順で、`$vmName = 'isucon13-bench'`を指定してログインする。

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
| `New-Isucon13VM.ps1` | アプリ用3台・ベンチ用1台を並列で構築 |
| `New-AutoinstallIso.ps1` | Ubuntu 26.04の一時コンテナでパッケージを更新し、xorrisoで無人インストール用ISOを生成 |
| `New-UbuntuVM.ps1` | 新規VMの作成、Ubuntuの無人インストール、SSH・sudo・cloud-initの確認 |
| `Invoke-Isucon13Ansible.ps1` | 必要なソフトウェアと公式ソースの取得、.testへの変更、各役割に必要なビルドと公式Ansibleの実行。アプリ用VMでは証明書を生成し、サービスを設定・起動。成功後にCPU・IOPSを設定して再起動 |

`New-Isucon13VM.ps1`は、インストール用ISOを一度生成して4台で共有する。
各VMで`New-UbuntuVM.ps1`の完了後に`Invoke-Isucon13Ansible.ps1`を呼び出す。
`Invoke-Isucon13Ansible.ps1`は、Ubuntu内で`scripts/guest/provision-isucon13.sh`を実行する。
公式Ansibleは、アプリ用VMには`application.yml`、ベンチ用VMには`benchmark.yml`を使用する。

ISOの生成にはWSLCの`ubuntu:26.04`を使用し、コンテナ内で`apt-get update`・`apt-get upgrade`後にxorrisoをインストールする。
コンテナは処理後に削除する。既存のWSLディストリビューションへのインストール操作は不要。

### 構築後のVMの構成（既定値）

| 項目 | アプリ用VM | ベンチ用VM |
| --- | --- | --- |
| 台数 | 3台 | 1台 |
| CPU | 各2 vCPU | 8 vCPU |
| メモリ方式 | 動的 | 動的 |
| 最小メモリ | 各512 MiB | 512 MiB |
| 起動時メモリ | 各2 GiB | 2 GiB |
| 最大メモリ | 各4 GiB | 8 GiB |
| ディスク容量 | 各40 GiB | 40 GiB |
| ディスク形式 | 4Kn VHDX（論理・物理セクター各4 KiB） | 4Kn VHDX（論理・物理セクター各4 KiB） |
| 最大IOPS | 各32000（Hyper-Vの8 KiB換算） | 制限なし |

構築中は全VMを4 vCPU・最小メモリ2 GiB・IOPS制限なしで稼働させる。
各VMのAnsibleが成功した後、シャットダウンして表のCPU・最小メモリ・IOPS設定を適用し、再起動する。
この再起動でIPが変わった場合は、アプリ用VMの環境変数とDNS設定を更新する。
Ansibleの再実行時も、構築中は4 vCPU・最小メモリ2 GiB・IOPS制限なしにし、成功後に構築後の設定へ戻す。

### 生成物と共通の設定

スクリプトは`-OutputPath`で指定したフォルダー内に、次の生成物を保存する。

| 生成物 | 保存先 |
| --- | --- |
| VMのディスク・設定 | `vm/<VM名>/` |
| SSH鍵・接続先の記録 | `ssh/` |
| ISO生成・Ansibleの実行ログ | `logs/` |

- 全VMでGeneration 2、Secure Boot無効を使用する。
- ボリュームシャドウコピー（VSS）とHyper-Vコンソールは初回起動前から無効。自動開始アクションはなし、自動停止アクションはシャットダウン。
- 管理ユーザーは`ubuntu`。公開鍵SSHとパスワード不要のsudoを設定する。
- ベンチは自己署名証明書を使えるよう、TLS証明書検証を省略する設定にする。
- 同名のVMや作成先のディスクが既にある場合は、上書きせずエラーで終了する。
- 構築中にエラーが発生したVMは処理を中断し、VMとディスクを残す。他のVMの構築は続行する。
- アプリ用VMで`Invoke-Isucon13Ansible.ps1`を再実行すると、証明書の再生成とDBの初期化も行う。

### 動作上の制約

- IOPS上限は、[gp3標準の3000 IOPS・125 MiB/s](https://docs.aws.amazon.com/ebs/latest/userguide/general-purpose.html)をこの制限によって下回らせないための保守的な値。[EBSが小さなI/Oを結合する場合](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-io-characteristics.html)も考慮し、4Knの最小I/Oを基準に`125 MiB/s ÷ 4 KiB = 32000`を採用している。データの読み書きでは、要求ごとの8 KiB換算の切り上げを含めても、換算数は転送量を4 KiBで割った値を超えない。
- 実性能はホストのストレージや同時負荷に依存する。gp3と同じ性能を再現する設定ではない。
- DNSには構築完了時のVMのIPv4アドレスを設定する。その後、DHCPでIPが変わった際の設定自動更新は未実装。
- `--pretest-only`ではベンチ結果のJSONを作成しない。

## 検証記録・参考

検証条件と結果は[検証記録](docs/validation.md)を参照。

- [公式ISUCON13](https://github.com/isucon/isucon13)
- [vagrant-isuconのVagrantfile](https://github.com/matsuu/vagrant-isucon/blob/master/isucon13-standalone/Vagrantfile)
- [wsl-isuconの構築スクリプト](https://github.com/matsuu/wsl-isucon/blob/main/isucon13/scripts/01-provisioning.sh)
