#!/usr/bin/env bash
set -euo pipefail

role=${1:-application}
case "$role" in
    application) playbook=application.yml ;;
    benchmarker) playbook=benchmark.yml ;;
    *) echo "Unknown role: $role" >&2; exit 1 ;;
esac

# Avoid Node 20.10/libuv io_uring hangs on Ubuntu's 5.15 kernel during builds.
export UV_USE_IO_URING=0

sudo -n cloud-init status --wait --long
sudo -n apt-get update
sudo -n env DEBIAN_FRONTEND=noninteractive apt-get install -y ansible curl git gnupg make snapd xz-utils

# Prepare build tools using the same packages as wsl-isucon.
sudo -n snap wait system seed.loaded
sudo -n snap install go --channel=1.21/stable --classic
export PATH="/snap/bin:$PATH"
sudo -n mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key |
    sudo -n gpg --batch --yes --dearmor -o /etc/apt/keyrings/nodesource.gpg
printf '%s\n' 'deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main' |
    sudo -n tee /etc/apt/sources.list.d/nodesource.list >/dev/null
sudo -n apt-get update
sudo -n env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends nodejs
sudo -n npm install -g corepack
sudo -n corepack enable

git clone --depth 1 https://github.com/isucon/isucon13.git /home/ubuntu/isucon13
cd /home/ubuntu/isucon13
# Local domain and locally issued TLS, following vagrant-isucon / wsl-isucon.
while IFS= read -r -d '' file; do
    sed -i 's/isucon\.dev/isucon.test/g' "$file"
done < <(git grep -Ilz 'isucon\.dev' -- bench frontend webapp provisioning envcheck)

# Advertise the fixed address instead of the Internet-facing DHCP address.
sed -i 's/ansible_default_ipv4.address/ansible_isucon.ipv4.address/' provisioning/ansible/roles/isucon-user/templates/env.sh
cp /home/ubuntu/tls/* provisioning/ansible/roles/nginx/files/etc/nginx/tls/
mv webapp/pdns/u.isucon.dev.zone webapp/pdns/u.isucon.test.zone
# The benchmarker does not trust the local CA, as in the reference environments.
sed -i '/InsecureSkipVerify/s/false/true/' bench/cmd/bench/benchmarker.go bench/cmd/bench/bench.go

# Prepare the assets required by the selected official playbook.
bash provisioning/ansible/make_latest_files.sh

# Remove the preparation tools before the official playbook installs its tools.
sudo -n env DEBIAN_FRONTEND=noninteractive apt-get purge -y nodejs
sudo -n rm -f /etc/apt/sources.list.d/nodesource.list /etc/apt/keyrings/nodesource.gpg
sudo -n snap remove --purge go

cd provisioning/ansible
ansible-playbook -i inventory/localhost --limit "$role" \
    --extra-vars '{"ansible_become_flags":"-H -S -n --preserve-env=UV_USE_IO_URING"}' "$playbook"
