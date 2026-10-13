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
sudo -n env DEBIAN_FRONTEND=noninteractive apt-get install -y ansible ca-certificates curl git gnupg liblzma-dev make snapd xz-utils

sudo -n mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key |
    sudo -n gpg --batch --yes --dearmor -o /etc/apt/keyrings/nodesource.gpg
printf '%s\n' 'deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main' |
    sudo -n tee /etc/apt/sources.list.d/nodesource.list >/dev/null
sudo -n apt-get update
sudo -n env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends nodejs
sudo -n npm install -g pnpm@9.15.9 @go-task/cli
sudo -n snap wait system seed.loaded
sudo -n snap install go --channel=1.23/stable --classic
export PATH="/snap/bin:$PATH"

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
    cp /home/ubuntu/tls/* "$tls_dir/"
fi

# The official script copies build/client into public; start with a fresh destination.
rm -rf webapp/public
bash provisioning/ansible/make_latest_files.sh

sudo -n snap remove --purge go
hash -r
sudo -n npm uninstall -g pnpm @go-task/cli
sudo -n env DEBIAN_FRONTEND=noninteractive apt-get purge -y nodejs
sudo -n rm -f /etc/apt/sources.list.d/nodesource.list /etc/apt/keyrings/nodesource.gpg

cd provisioning/ansible
ansible-playbook -i inventory/localhost --limit "$role" "${playbooks[@]}"

if test "$role" = application; then
    sudo -n systemctl daemon-reload
    sudo -n systemctl restart isuride-matcher
fi
