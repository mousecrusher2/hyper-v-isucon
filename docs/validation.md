# 実機検証記録

検証日: 2026-09-30（JST）

## 条件

| 項目 | 使用した構成 |
| --- | --- |
| ホスト | Windows 11 Pro＋Hyper-V、PowerShell 7.6.6 |
| ISO | `D:\iso\ubuntu-22.04.5-live-server-amd64.iso` |
| 仮想スイッチ | `Default Switch` |
| golden作成用VM | Generation 2、2 vCPU、固定4 GiB、64 GiB dynamic VHDX、Secure Boot無効 |
| ubuntu-clone01 | 8 vCPU、固定8 GiB。公式Ansible実行先 |
| ubuntu-clone02 | 2 vCPU、固定4 GiB。素Ubuntuのまま保持 |
| ISUCON13 commit | `8f6afdc3603f0c661368de4659a7240862f59623` |

Packer、differencing VHDX、QCOW2変換は使用していない。
インストーラーの手動操作も行っていない。

## golden作成

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
| 成果物 | VHDX・Dynamic、ParentPathなし、Attached=False |

成果物は`golden/ubuntu-server-22.04/disk.vhdx`。
ISUCON13・Ansibleは含まない。最終版から起動したcloneでも未導入を確認した。

最終版goldenのSHA-256（clone作成前後で一致）:

```text
4CF62E21CB9BF1B0055A035BF04D829EDA8487D47EBB02FC7601CC54FC185AB6
```

ログ: `.local/results/golden-build-final.log`

## cloneの独立性

`New-UbuntuVM.ps1`によるフルコピーと`Test-UbuntuClones.ps1`による検証に成功した。
両VMのNoCloud instance-idは各seedの指定値と一致し、cloud-initはerrorsなしで完了した。
SSH・sudo・UEFI起動も確認した。

| VM | machine-id |
| --- | --- |
| ubuntu-clone01 | `8eaefa9dfa4b4910adbd374e19eec26e` |
| ubuntu-clone02 | `21c2dae62bc44bc093d15e6d5cd17669` |

VM ID・MAC・SSH host key・instance-idもすべて異なった。
両VMのVHDXに親ディスクはなく、自動checkpointは無効。
goldenの再ビルド後、ubuntu-clone02は最終版goldenから作り直して検証した。

記録: `.local/results/clone-verification.json`

## cloneへの公式Ansible

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

## .test・自己署名TLS

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

## 残る事項

- 自己署名証明書をブラウザで使うには、証明書を信頼するか警告を許可する必要がある。
- Hyper-VではAWSのpublic IP取得処理が働かない。現在はAnsible実行時のclone IPv4が設定される。DHCPでIPが変わった場合の更新方法は未実装。
