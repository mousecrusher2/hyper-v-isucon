#!/usr/bin/env bash
set -euo pipefail

test "$(id -un)" = ubuntu
sudo -n cloud-init status --wait --long
sudo -n apt-get update
sudo -n env DEBIAN_FRONTEND=noninteractive apt-get install -y ansible curl git make openssl xz-utils

# Prepare tools through the same xbuild project used by official ISUCON13.
if test ! -d /home/ubuntu/xbuild/.git; then
    git clone --depth 1 https://github.com/tagomoris/xbuild.git /home/ubuntu/xbuild
fi
/home/ubuntu/xbuild/go-install 1.21.2 /home/ubuntu/local/golang
/home/ubuntu/xbuild/node-install v20.10.0 /home/ubuntu/local/node
export PATH="/home/ubuntu/local/golang/bin:/home/ubuntu/local/node/bin:$PATH"

if test ! -d /home/ubuntu/isucon13/.git; then
    git clone --depth 1 https://github.com/isucon/isucon13.git /home/ubuntu/isucon13
fi
cd /home/ubuntu/isucon13
git rev-parse HEAD
# Local domain and self-signed TLS, following vagrant-isucon / wsl-isucon.
while IFS= read -r -d '' file; do
    sed -i 's/isucon\.dev/isucon.test/g' "$file"
done < <(git grep -Ilz 'isucon\.dev' -- bench frontend webapp provisioning envcheck)

tls_dir=provisioning/ansible/roles/nginx/files/etc/nginx/tls
for domain in u t; do
    openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
        -subj "/CN=*.$domain.isucon.test" \
        -addext "subjectAltName=DNS:*.$domain.isucon.test" \
        -keyout "$tls_dir/_.$domain.isucon.test.key" \
        -out "$tls_dir/_.$domain.isucon.test.crt"
    cp "$tls_dir/_.$domain.isucon.test.crt" "$tls_dir/_.$domain.isucon.test.issuer.crt"
done
if test -f webapp/pdns/u.isucon.dev.zone; then
    mv webapp/pdns/u.isucon.dev.zone webapp/pdns/u.isucon.test.zone
fi
# The reference environments also disable verification for self-signed TLS.
sed -i '/InsecureSkipVerify/s/false/true/' bench/cmd/bench/benchmarker.go bench/cmd/bench/bench.go

# Reuse official asset preparation and application provisioning.
bash provisioning/ansible/make_latest_files.sh
cd provisioning/ansible
ansible-playbook -i inventory/localhost --limit application application.yml
