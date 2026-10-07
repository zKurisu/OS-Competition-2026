#!/usr/bin/env bash
# Destructive only after an explicit target disk, backup directory and confirmation.
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"

usage() {
  echo "usage: sudo $0 starry|linux /dev/sdX BACKUP_DIR --confirm"
  echo "  starry: back up the current FAT boot.sd, then replace only that file."
  echo "  linux: back up the whole card, then write the verified baseline disk image."
}
[[ $# == 4 && $4 == --confirm ]] || { usage >&2; exit 2; }
os=$1; device=$2; backup_dir=$3
case_root "$os" >/dev/null
(( EUID == 0 )) || die "run this script with sudo"
need_cmd lsblk
need_cmd sha256sum
[[ $device == /dev/* && -b $device ]] || die "not a block device: $device"
[[ $(lsblk -dnro TYPE "$device") == disk ]] || die "target must be a whole disk"
[[ $(lsblk -dnro RM "$device") == 1 ]] || die "target is not removable"
[[ -z $(lsblk -nrpo MOUNTPOINTS "$device" | sed '/^$/d') ]] || die "unmount all card partitions first"
lsblk -d -o NAME,PATH,RM,TRAN,SIZE,MODEL "$device"
[[ -d $backup_dir ]] || die "create backup directory on a different disk first: $backup_dir"
backup_dir=$(realpath -- "$backup_dir")
[[ $backup_dir != "$REPRO_OUTPUT_DIR" ]] || die "use a dedicated backup directory"

if [[ $os == linux ]]; then
  image="$LINUX_BASE_ROOT/images/v0.4/linux-baseline-640.img"
  need_file "$image"
  need_file "$image.sha256"
  (cd "$(dirname -- "$image")" && sha256sum -c "$(basename -- "$image.sha256")")
  backup="$backup_dir/card-before-linux-flash.img"
  [[ ! -e $backup ]] || die "backup path already exists: $backup"
  need_cmd blockdev
  bytes=$(blockdev --getsize64 "$device")
  available=$(df -PB1 "$backup_dir" | awk 'NR==2 {print $4}')
  (( available > bytes )) || die "backup directory needs more than $bytes free bytes"
  dd if="$device" of="$backup" bs=1M iflag=fullblock status=progress conv=fsync
  [[ $(stat -c %s "$backup") == "$bytes" ]] || die "card backup is incomplete"
  sha256sum "$backup" >"$backup.sha256"
  AKARS_FLASH_CONFIRM=YES "$LINUX_BASE_ROOT/scripts/flash-linux-baseline.sh" "$device"
  printf 'BACKUP=%s\n' "$backup"
  exit 0
fi

need_cmd dumpimage
need_cmd mount
boot="$REPRO_OUTPUT_DIR/starry/boot.sd"
need_file "$boot"
new_fit=$(dumpimage -l "$boot")
[[ $new_fit == *'kernel-1'* && $new_fit == *'fdt-1'* && $new_fit == *'config-sg2002_licheervnano_sd'* ]] || die "new FIT lacks kernel/FDT/config"
mapfile -t partitions < <(lsblk -nrpo PATH,TYPE "$device" | awk '$2=="part" {print $1}')
((${#partitions[@]} >= 2)) || die "expected boot and rootfs partitions"
boot_part=${partitions[0]}
[[ $(lsblk -dnro FSTYPE "$boot_part") == vfat ]] || die "first partition is not FAT"
mountpoint=$(mktemp -d)
mounted=0
cleanup() {
  if ((mounted)); then umount -- "$mountpoint"; fi
  rmdir -- "$mountpoint"
}
trap cleanup EXIT
mount -o ro "$boot_part" "$mountpoint"
mounted=1
need_file "$mountpoint/boot.sd"
old_fit=$(dumpimage -l "$mountpoint/boot.sd")
[[ $old_fit == *'starryos kernel'* && $old_fit == *'fdt-1'* ]] || die "card does not contain a verified StarryOS FIT"
backup="$backup_dir/boot.sd.before-starry-update"
[[ ! -e $backup ]] || die "backup path already exists: $backup"
cp -- "$mountpoint/boot.sd" "$backup"
sha256sum "$backup" >"$backup.sha256"
cmp -- "$mountpoint/boot.sd" "$backup" || die "boot backup verification failed"
umount -- "$mountpoint"
mounted=0
mount "$boot_part" "$mountpoint"
mounted=1
free_bytes=$(df -PB1 "$mountpoint" | awk 'NR==2 {print $4}')
new_bytes=$(stat -c %s "$boot")
old_bytes=$(stat -c %s "$mountpoint/boot.sd")
(( free_bytes + old_bytes > new_bytes )) || die "boot partition lacks space for replacement"
# The 16 MiB FAT partition cannot hold two FITs. The verified backup is on the host.
rm -- "$mountpoint/boot.sd"
cp -- "$boot" "$mountpoint/boot.sd"
sync
cmp -- "$boot" "$mountpoint/boot.sd" || die "boot.sd readback mismatch; keep card out of robot"
printf 'STARRY_BOOT_UPDATED=%s\nBACKUP=%s\n' "$boot_part" "$backup"
