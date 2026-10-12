#!/bin/sh
set -eu
sudo -n true
sudo -n cloud-init status --wait --long
. /etc/os-release
test "$ID" = ubuntu && test "$VERSION_ID" = 22.04
test -d /sys/firmware/efi
test -z "$(swapon --show --noheadings)"
systemctl is-active --quiet ssh
