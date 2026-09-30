#!/usr/bin/env bash
set -euo pipefail

test "$(id -u)" -eq 0
cloud-init status --wait --long
# Subiquity's DataSourceNone setting would prevent clone NoCloud detection.
rm -f /etc/cloud/cloud.cfg.d/99-installer.cfg
# Identity and SSH host keys are recreated by stock cloud-init on clone boot.
cloud-init clean --logs --machine-id
printf 'GENERALIZE_COMPLETE\n'
poweroff
