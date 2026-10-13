#!/usr/bin/env bash
set -euo pipefail

role=${1:-application}
case "$role" in
    application) playbooks=(application-base.yml application.yml) ;;
    benchmarker) playbooks=(benchmark.yml) ;;
    *) echo "Unknown role: $role" >&2; exit 1 ;;
esac

test "$(id -un)" = ubuntu
. /etc/os-release
test "$ID" = ubuntu && test "$VERSION_ID" = 24.04
sudo -n cloud-init status --wait --long
sudo -n apt-get update
sudo -n env DEBIAN_FRONTEND=noninteractive apt-get install -y ansible ca-certificates curl git gnupg liblzma-dev make openssl snapd xz-utils

if test "$role" = application; then
    sudo -n mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key |
        sudo -n gpg --batch --yes --dearmor -o /etc/apt/keyrings/nodesource.gpg
    printf '%s\n' 'deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main' |
        sudo -n tee /etc/apt/sources.list.d/nodesource.list >/dev/null
    sudo -n apt-get update
    sudo -n env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends nodejs
    sudo -n npm install -g pnpm@9.15.9
else
    sudo -n snap wait system seed.loaded
    sudo -n snap install go --channel=1.23/stable --classic
    export PATH="/snap/bin:$PATH"
fi

if test ! -d /home/ubuntu/isucon14/.git; then
    git clone --depth 1 https://github.com/isucon/isucon14.git /home/ubuntu/isucon14
fi
cd /home/ubuntu/isucon14
git rev-parse HEAD
while IFS= read -r -d '' file; do
    sed -i 's/xiv\.isucon\.net/xiv.isucon.test/g' "$file"
done < <(git grep -Ilz 'xiv\.isucon\.net' -- bench frontend webapp provisioning)

if test -f /etc/apt/sources.list.d/ubuntu.sources; then
    sed -i 's|path: /etc/apt/sources.list$|path: /etc/apt/sources.list.d/ubuntu.sources|' provisioning/ansible/roles/apt/tasks/main.yml
fi

if test "$role" = application; then
    sed -i '/^    - isuadmin-user$/d; /^    - envcheck$/d' provisioning/ansible/application.yml
    sed -i 's/curl -s https:/curl -k -s https:/' provisioning/ansible/roles/webapp/files/isuride-matcher.service
    tls_dir=provisioning/ansible/roles/nginx/files/etc/nginx/tls
    # Serve the leaf and intermediate, as in production.
    ca_dir=$(mktemp -d)
    trap 'rm -rf "$ca_dir"' EXIT
    cat >"$ca_dir/ext.cnf" <<EOF
[root]
basicConstraints = critical, CA:true
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash

[intermediate]
keyUsage = critical, keyCertSign, cRLSign
basicConstraints = critical, CA:true, pathlen:0
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always

[leaf]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
basicConstraints = critical, CA:false
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
subjectAltName = DNS:*.xiv.isucon.test, DNS:xiv.isucon.test
EOF
    # issue <name> <genpkey options> <subject> <extension section> [<issuer name>]
    issue() {
        local -a key_options signer
        read -ra key_options <<<"$2"
        openssl genpkey "${key_options[@]}" -out "$ca_dir/$1.key"
        openssl req -new -key "$ca_dir/$1.key" -subj "$3" -out "$ca_dir/$1.csr"
        signer=(-signkey "$ca_dir/$1.key")
        if test -n "${5:-}"; then
            signer=(-CA "$ca_dir/$5.crt" -CAkey "$ca_dir/$5.key")
        fi
        openssl x509 -req -in "$ca_dir/$1.csr" "${signer[@]}" -sha256 -days 3650 \
            -extfile "$ca_dir/ext.cnf" -extensions "$4" -out "$ca_dir/$1.crt"
    }
    rsa2048='-algorithm RSA -pkeyopt rsa_keygen_bits:2048'
    issue root-x1 '-algorithm RSA -pkeyopt rsa_keygen_bits:4096' '/C=JP/O=hyper-isucon Certificate Authority/CN=Root X1' root
    issue r10 "$rsa2048" '/C=JP/O=hyper-isucon/CN=R10' intermediate root-x1
    issue xiv "$rsa2048" '/CN=*.xiv.isucon.test' leaf r10
    openssl verify -CAfile "$ca_dir/root-x1.crt" -untrusted "$ca_dir/r10.crt" \
        -purpose sslserver -verify_hostname isuride.xiv.isucon.test "$ca_dir/xiv.crt"
    cp "$ca_dir/xiv.key" "$tls_dir/_.xiv.isucon.test.key"
    cat "$ca_dir/xiv.crt" "$ca_dir/r10.crt" >"$tls_dir/_.xiv.isucon.test.crt"
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -sha256 -days 3650 \
        -subj '/CN=isucon.net' \
        -keyout "$tls_dir/dummy.key" -out "$tls_dir/dummy.crt"

    make -C frontend
    mkdir -p webapp/public provisioning/ansible/roles/webapp/files
    cp -r frontend/build/client/. webapp/public/
    tar -zcf provisioning/ansible/roles/webapp/files/webapp.tar.gz webapp

    sudo -n npm uninstall -g pnpm
    sudo -n env DEBIAN_FRONTEND=noninteractive apt-get purge -y nodejs
    sudo -n rm -f /etc/apt/sources.list.d/nodesource.list /etc/apt/keyrings/nodesource.gpg
else
    client=bench/benchmarker/webapp/client.go
    if ! grep -Fq '"crypto/tls"' "$client"; then
        sed -i '/"context"/a\	"crypto/tls"' "$client"
    fi
    if ! grep -Fq 'InsecureSkipVerify: true' "$client"; then
        sed -i '/trs := agent.DefaultTransport.Clone()/a\	trs.TLSClientConfig = \&tls.Config{InsecureSkipVerify: true}' "$client"
    fi
    gofmt -w "$client"
    mkdir -p provisioning/ansible/roles/bench/files
    (
        cd bench
        GOOS=linux GOARCH=amd64 go build -ldflags '-s -w' \
            -o ../provisioning/ansible/roles/bench/files/bench_linux_amd64
    )
    sudo -n snap remove --purge go
    hash -r
fi

cd provisioning/ansible
ansible-playbook -i inventory/localhost --limit "$role" "${playbooks[@]}"

if test "$role" = application; then
    sudo -n systemctl daemon-reload
    sudo -n systemctl restart isuride-matcher
fi
