# 実機検証記録

検証日: 2026-09-30（JST）

## 現行構成

`New-Isucon13VM.ps1`で、アプリ用3台・ベンチ用1台をISOから無人インストールし、
各VMに役割に応じた公式Ansibleを実行する。

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

### 4台構成とベンチ用VM

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

Hyper-V側でも次の設定を確認した。

- VSS連携: `Enabled=False`。
- 自動停止アクション: `ShutDown`。
- 仮想ディスプレイ・キーボード・マウス: なし。

ホストからの正常シャットダウンに成功した。検証用VMとディスクは削除済み。

記録:

- `.local/results/vm-settings-build.log`
- `.local/results/vm-settings-check.json`
- `.local/results/vm-settings-cleanup.json`

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
