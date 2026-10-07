#!/usr/bin/env bash
# Configure STA Wi-Fi on a powered-off SG2002 TF card, without storing secrets in Git.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

usage() { echo "usage: sudo $0 starry|linux /dev/sdX BACKUP_DIR --confirm"; }
[[ $# == 4 && $4 == --confirm ]] || { usage >&2; exit 2; }
os=$1; device=$2; backup_dir=$3
case_root "$os" >/dev/null
(( EUID == 0 )) || die "run with sudo"
for tool in lsblk mount umount dumpimage install; do need_cmd "$tool"; done
[[ -b $device && $device == /dev/* ]] || die "specify a block device"
[[ $(lsblk -dnro TYPE "$device") == disk && $(lsblk -dnro RM "$device") == 1 ]] || die "target must be a removable whole disk"
[[ -z $(lsblk -nrpo MOUNTPOINTS "$device" | sed '/^$/d') ]] || die "unmount card partitions first"
[[ -d $backup_dir ]] || die "backup directory does not exist: $backup_dir"
backup_dir=$(realpath -- "$backup_dir")
[[ -t 0 ]] || die "run from an interactive terminal so the password is not passed as an argument"
printf 'SSID (2.4 GHz network): ' >&2
IFS= read -r ssid
printf 'Wi-Fi password (hidden): ' >&2
IFS= read -r -s psk
printf '\n' >&2
LC_ALL=C
export LC_ALL
(( ${#ssid} >= 1 && ${#ssid} <= 32 )) || die "SSID must be 1-32 bytes"
(( ${#psk} >= 8 && ${#psk} <= 63 )) || die "WPA2 password must be 8-63 bytes"
[[ $ssid != *$'\r'* && $psk != *$'\r'* ]] || die "carriage return is not allowed"
lsblk -d -o NAME,PATH,RM,TRAN,SIZE,MODEL "$device"

mapfile -t parts < <(lsblk -nrpo PATH,TYPE,FSTYPE "$device" | awk '$2=="part" {print $1 " " $3}')
((${#parts[@]} >= 2)) || die "expected at least boot and rootfs partitions"
read -r boot_part boot_fs <<<"${parts[0]}"
[[ $boot_fs == vfat ]] || die "first partition is not FAT"
backup="$backup_dir/wifi-before-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -m 700 -- "$backup"
mnt=$(mktemp -d)
mounted=0
cleanup() {
  if ((mounted)); then umount -- "$mnt"; fi
  rmdir -- "$mnt"
}
trap cleanup EXIT

if [[ $os == linux ]]; then
  mount -o ro "$boot_part" "$mnt"
  mounted=1
  # A StarryOS FIT on this card means the wrong card/mode was selected.
  if [[ -f $mnt/boot.sd ]] && dumpimage -l "$mnt/boot.sd" 2>/dev/null | grep -q 'starryos kernel'; then
    die "this is a StarryOS card, not a Linux baseline card"
  fi
  for name in wifi.sta wifi.ssid wifi.pass wpa_supplicant.conf; do
    if [[ -e $mnt/$name ]]; then cp -p -- "$mnt/$name" "$backup/$name"; fi
  done
  umount -- "$mnt"
  mounted=0
  mount "$boot_part" "$mnt"
  mounted=1
  : >"$mnt/wifi.sta"
  printf '%s\n' "$ssid" >"$mnt/wifi.ssid"
  printf '%s\n' "$psk" >"$mnt/wifi.pass"
  # Let the vendor S30wifi regenerate WPA settings from wifi.ssid/wifi.pass.
  if [[ -f $mnt/wpa_supplicant.conf ]]; then rm -- "$mnt/wpa_supplicant.conf"; fi
  sync
  [[ $(sed -n '1p' "$mnt/wifi.ssid") == "$ssid" && $(sed -n '1p' "$mnt/wifi.pass") == "$psk" ]] || die "Wi-Fi readback failed"
  printf 'WIFI_CARD_CONFIGURED os=linux backup=%s\n' "$backup"
  exit 0
fi

# StarryOS: the boot FIT must have Wi-Fi support and an ext4 rootfs.
mount -o ro "$boot_part" "$mnt"
mounted=1
[[ -f $mnt/boot.sd ]] || die "StarryOS boot.sd is missing"
dumpimage -l "$mnt/boot.sd" | grep -q 'starryos kernel' || die "card is not StarryOS"
umount -- "$mnt"
mounted=0
root_part=
for part in "${parts[@]:1}"; do
  read -r path fstype <<<"$part"
  if [[ $fstype == ext4 ]]; then root_part=$path; break; fi
done
[[ -n $root_part ]] || die "no ext4 StarryOS rootfs partition found"
switch_binary="$REPRO_OUTPUT_DIR/starry/wifi_switch"
need_file "$switch_binary"
mount -o ro "$root_part" "$mnt"
mounted=1
[[ -d $mnt/root && -d $mnt/usr/bin ]] || die "unexpected StarryOS rootfs layout"
for name in init.sh akars-wifi.ssid akars-wifi.pass akars-wifi-start.sh; do
  if [[ -e $mnt/root/$name ]]; then cp -p -- "$mnt/root/$name" "$backup/$name"; fi
done
if [[ -e $mnt/usr/bin/wifi_switch ]]; then cp -p -- "$mnt/usr/bin/wifi_switch" "$backup/wifi_switch"; fi
umount -- "$mnt"
mounted=0
mount "$root_part" "$mnt"
mounted=1
install -m 755 -- "$switch_binary" "$mnt/usr/bin/wifi_switch"
printf '%s\n' "$ssid" >"$mnt/root/akars-wifi.ssid"
printf '%s\n' "$psk" >"$mnt/root/akars-wifi.pass"
chmod 600 "$mnt/root/akars-wifi.ssid" "$mnt/root/akars-wifi.pass"
install -m 700 -- "$TESTS_ROOT/starry-wifi-start.sh" "$mnt/root/akars-wifi-start.sh"
if [[ ! -f $mnt/root/init.sh ]]; then
  printf '#!/bin/sh\n/root/akars-wifi-start.sh\n' >"$mnt/root/init.sh"
elif ! grep -q '^# AKARS_WIFI_MANAGED_START$' "$mnt/root/init.sh"; then
  # Preserve the existing board startup script and run it first. The wrapper
  # then applies the explicitly selected Wi-Fi network last.
  [[ ! -e $mnt/root/init.sh.before-akars-wifi ]] || die "existing Wi-Fi wrapper backup needs manual review"
  mv -- "$mnt/root/init.sh" "$mnt/root/init.sh.before-akars-wifi"
  printf '#!/bin/sh\n# AKARS_WIFI_MANAGED_START\n/bin/sh /root/init.sh.before-akars-wifi\n/root/akars-wifi-start.sh\n' >"$mnt/root/init.sh"
fi
chmod 700 "$mnt/root/init.sh"
sync
[[ $(sed -n '1p' "$mnt/root/akars-wifi.ssid") == "$ssid" && $(sed -n '1p' "$mnt/root/akars-wifi.pass") == "$psk" ]] || die "Wi-Fi readback failed"
printf 'WIFI_CARD_CONFIGURED os=starry backup=%s\n' "$backup"
