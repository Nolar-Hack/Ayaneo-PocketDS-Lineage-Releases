#!/usr/bin/env bash
set -euo pipefail

# Back up the running stock ROM of an Ayaneo Pocket DS over adb, before
# flashing LineageOS. Needs root on the device (KernelSU / Magisk "su").
#
# Saves, for the ACTIVE slot only:
#   - raw partitions:     boot init_boot vendor_boot dtbo recovery vbmeta vbmeta_system
#   - logical partitions: system system_ext product vendor odm vendor_dlkm system_dlkm
# plus device-unique calibration data that must never be lost:
#   persist modemst1 modemst2 fsg fsc
# Restore with scripts/restore-stock.sh <backup dir>.

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { error "$@"; exit 1; }
step()  { echo -e "${CYAN}[STEP]${NC} $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# In the project the copy goes to Backup/Original/stock-backups; run on its own (the recovery/ folder
# of the releases repository) it goes to a folder next to where you run it.
if [[ -d "$ROOT_DIR/../Backup/Original" ]]; then
    DEFAULT_OUT="$ROOT_DIR/../Backup/Original/stock-backups/backup-$(date +%Y%m%d-%H%M%S)"
else
    DEFAULT_OUT="./stock-backup-$(date +%Y%m%d-%H%M%S)"
fi
OUT_DIR="${1:-$DEFAULT_OUT}"

command -v adb &>/dev/null || die "Required tool not found: adb"
adb devices | grep -q 'device$' || die "No device found via adb"
adb shell su -c true 2>/dev/null || die "Root (su) is required on the device"

[[ "$(adb shell getprop ro.board.platform | tr -d '\r')" == "kalama" ]] \
    || die "This does not look like a Pocket DS (ro.board.platform != kalama)"

SLOT="$(adb shell getprop ro.boot.slot_suffix | tr -d '\r')"
[[ -n "$SLOT" ]] || die "Could not read the active slot"

mkdir -p "$OUT_DIR"
info "Backing up slot ${SLOT} to $OUT_DIR"

# dd straight to the host; exec-out keeps the stream binary-safe.
dump() {
    local src="$1" dst="$2"
    step "$(basename "$dst")"
    adb exec-out su -c "dd if=$src bs=4194304 2>/dev/null" > "$OUT_DIR/$dst"
    [[ -s "$OUT_DIR/$dst" ]] || die "Empty dump for $src"
}

for p in boot init_boot vendor_boot dtbo recovery vbmeta vbmeta_system; do
    dump "/dev/block/by-name/${p}${SLOT}" "${p}.img"
done

for p in system system_ext product vendor odm vendor_dlkm system_dlkm; do
    dump "/dev/block/mapper/${p}${SLOT}" "${p}.img"
done

for p in persist modemst1 modemst2 fsg fsc; do
    dump "/dev/block/by-name/${p}" "${p}.img"
done

{
    echo "slot=${SLOT}"
    echo "fingerprint=$(adb shell getprop ro.build.fingerprint | tr -d '\r')"
    echo "kernel=$(adb shell uname -r | tr -d '\r')"
    echo "date=$(date -Iseconds)"
} > "$OUT_DIR/backup-info.txt"

(cd "$OUT_DIR" && sha256sum ./*.img > SHA256SUMS)

ok "Backup complete: $OUT_DIR ($(du -sh "$OUT_DIR" | cut -f1))"
info "Copy it somewhere safe — persist/modemst*/fsg/fsc are unique to this device."
