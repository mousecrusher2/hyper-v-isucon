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
    tls_dir=provisioning/ansible/roles/nginx/files/etc/nginx/tls
    openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
        -subj '/CN=*.xiv.isucon.test' \
        -addext 'basicConstraints=critical,CA:true,pathlen:0' \
        -addext 'subjectAltName=DNS:*.xiv.isucon.test,DNS:xiv.isucon.test' \
        -keyout "$tls_dir/_.xiv.isucon.test.key" -out "$tls_dir/_.xiv.isucon.test.crt"
    openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
        -subj '/CN=localhost' -addext 'subjectAltName=DNS:localhost' \
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
    sudo -n install -m 0644 /etc/nginx/tls/_.xiv.isucon.test.crt /usr/local/share/ca-certificates/isuride.crt
    sudo -n update-ca-certificates
    sudo -n systemctl restart isuride-matcher
fi
