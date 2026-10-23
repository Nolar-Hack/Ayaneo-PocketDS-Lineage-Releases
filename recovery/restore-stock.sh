#!/usr/bin/env bash
set -euo pipefail

# Restore a backup made by scripts/backup-stock.sh, from fastbootd.
# Calibration partitions (persist, modemst*, fsg, fsc) are NOT touched here;
# they are only kept in the backup for disaster recovery.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { error "$@"; exit 1; }
step()  { echo -e "${CYAN}[STEP]${NC} $*"; }

BACKUP_DIR="${1:-}"
[[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]] || die "Usage: $(basename "$0") <backup dir>"
command -v fastboot &>/dev/null || die "Required tool not found: fastboot"

(cd "$BACKUP_DIR" && sha256sum --quiet -c SHA256SUMS) || die "Backup checksum mismatch"

warn "This restores the stock ROM on the CURRENT slot and wipes user data."
read -rp "Continue? [y/N] " response
[[ "$response" =~ ^[Yy]$ ]] || die "Aborted by user"

# The Pocket DS bootloader fastboot rejects "flash": go to fastbootd.
if adb devices 2>/dev/null | grep -q 'device$'; then
    adb reboot fastboot
fi
info "Waiting for fastboot..."
until fastboot devices 2>/dev/null | grep -q fastboot; do sleep 1; done
if ! fastboot getvar is-userspace 2>&1 | grep -q 'is-userspace: yes'; then
    fastboot reboot fastboot
    sleep 5
    until fastboot devices 2>/dev/null | grep -q fastboot; do sleep 1; done
fi
fastboot getvar is-userspace 2>&1 | grep -q 'is-userspace: yes' || die "Device did not enter fastbootd"

fastboot snapshot-update cancel || true

for p in vbmeta vbmeta_system boot init_boot vendor_boot dtbo recovery \
         system system_ext product vendor odm vendor_dlkm system_dlkm; do
    step "Flashing $p..."
    fastboot flash "$p" "$BACKUP_DIR/$p.img"
done

step "Wiping userdata + metadata..."
fastboot -w

# fastbootd on this device does not flush its writes before rebooting: wait for
# the kernel write-back, or the last images written are lost.
step "Waiting 90s for the writes to reach storage..."
sleep 90
fastboot reboot

ok "Stock ROM restored."
