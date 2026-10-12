#!/bin/sh
set -eu

task_output=$1
task_work=$(mktemp -d)
trap 'rm -rf "$task_work"' EXIT
xorriso -no_rc -osirrox on -indev /input/source.iso \
  -extract /boot/grub/grub.cfg "$task_work/grub.cfg" \
  -extract /md5sum.txt "$task_work/md5sum.txt"

sed -E '
  /^[[:space:]]*set timeout=/s/=.*/=0/
  /^[[:space:]]*linux[[:space:]]/ {
    /[[:space:]]autoinstall([[:space:]]|$)/! s/[[:space:]]+---([[:space:]]|$)/ autoinstall ---\1/
  }
' "$task_work/grub.cfg" > "$task_work/grub-autoinstall.cfg"
grep -Eq '^[[:space:]]*set timeout=0([[:space:]]|$)' "$task_work/grub-autoinstall.cfg"
grep -Eq '^[[:space:]]*linux[[:space:]]' "$task_work/grub-autoinstall.cfg"
if grep -E '^[[:space:]]*linux[[:space:]]' "$task_work/grub-autoinstall.cfg" |
   grep -Ev '[[:space:]]autoinstall([[:space:]]|$)'; then
  echo 'Could not add autoinstall to every kernel entry' >&2
  exit 1
fi

grep -Eq '^[0-9a-f]{32}  \./boot/grub/grub\.cfg$' "$task_work/md5sum.txt"
task_hash=$(md5sum "$task_work/grub-autoinstall.cfg" | cut -d ' ' -f 1)
sed -E "s|^[0-9a-f]{32}(  \./boot/grub/grub\.cfg)$|$task_hash\1|" \
  "$task_work/md5sum.txt" > "$task_work/md5sum-autoinstall.txt"
xorriso -no_rc -indev /input/source.iso -outdev "$task_output" \
  -map "$task_work/grub-autoinstall.cfg" /boot/grub/grub.cfg \
  -map "$task_work/md5sum-autoinstall.txt" /md5sum.txt \
  -boot_image any replay

xorriso -no_rc -osirrox on -indev "$task_output" \
  -report_el_torito plain -report_system_area plain \
  -extract /boot/grub/grub.cfg "$task_work/grub-verified.cfg" \
  -extract /md5sum.txt "$task_work/md5sum-verified.txt"
test "$(md5sum "$task_work/grub-verified.cfg" | cut -d ' ' -f 1)" = "$task_hash"
test "$(sha256sum "$task_work/md5sum-verified.txt" | cut -d ' ' -f 1)" = \
     "$(sha256sum "$task_work/md5sum-autoinstall.txt" | cut -d ' ' -f 1)"
