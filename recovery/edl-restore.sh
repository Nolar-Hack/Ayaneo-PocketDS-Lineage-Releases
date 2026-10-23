#!/usr/bin/env bash
set -euo pipefail

# Writes some partitions back from a safety copy made by edl-backup.sh, in EDL.
#
#   edl-restore.sh --tools <flat build folder or zip> --copy <safety copy folder> --slot a|b
#                  --set firmware[,android] | --labels label,label  [--port /dev/ttyUSB0]
#                  [--skip-load] [--yes] [--dry-run]
#
# What it writes is only what you choose:
#   --set firmware   the firmware of one slot (abl aop aop_config bluetooth cpucp devcfg dsp featenabler
#                    hyp imagefv keymaster mdtp mdtpsecapp modem qupfw qweslicstore rticmpdata shrm tz
#                    uefi uefisecapp vm-bootsys xbl_ramdump): what brought the development console back
#   --set android    boot init_boot vendor_boot dtbo vbmeta vbmeta_system of that slot
#   --labels         exact partition names (for example abl_a,tz_a)
# Every write is read back and compared with the copy; the script stops at the first difference.
#
# It never writes: persist, modemst1, modemst2, fsg, fsc, devinfo, xbl, the partition tables, userdata,
# super, metadata. Put the console in EDL first (Vol+ and Vol- while plugging the USB cable).
#
# Start from the slot that is broken, and only that one. Do not restore a slot that works.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COPY=""; TOOLS=""; PORT=""; SLOT=""; SETS=""; LABELS=""
SKIP_LOAD=false; ASSUME_YES=false; DRY_RUN=false

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tools) TOOLS="$2"; shift ;;
        --copy) COPY="$2"; shift ;;
        --slot) SLOT="$2"; shift ;;
        --set) SETS="$2"; shift ;;
        --labels) LABELS="$2"; shift ;;
        --port) PORT="$2"; shift ;;
        --skip-load) SKIP_LOAD=true ;;
        --yes) ASSUME_YES=true ;;
        --dry-run) DRY_RUN=true ;;
        -h|--help) sed -n 4,24p "$0"; exit 0 ;;
        *) die "Unknown option: $1" ;;
    esac
    shift
done

[[ -d "$COPY" ]] && COPY="$(cd "$COPY" && pwd)"
[[ -n "$TOOLS" ]] && TOOLS="$(readlink -f "$TOOLS")"
[[ -d "$COPY" && -f "$COPY/restore.xml" ]] || die "--copy must be a safety copy folder made by edl-backup.sh (restore.xml inside)"
[[ -n "$SETS$LABELS" ]] || die "Say what to write: --set firmware|android or --labels ..."
[[ -z "$SETS" || "$SLOT" == a || "$SLOT" == b ]] || die "--set needs --slot a or --slot b"

# The copy must be the one that was written down: check it before anything is written.
if [[ -f "$COPY/SHA256SUMS" ]]; then
    info "Checking the copy against SHA256SUMS"
    ( cd "$COPY" && sha256sum --quiet -c SHA256SUMS ) || die "The safety copy is damaged (SHA256SUMS does not match): do not use it"
    ok "The copy is intact"
else
    warn "No SHA256SUMS in the copy: its integrity is not checked"
fi

FIRMWARE="abl aop aop_config bluetooth cpucp devcfg dsp featenabler hyp imagefv keymaster mdtp mdtpsecapp modem qupfw qweslicstore rticmpdata shrm tz uefi uefisecapp vm-bootsys xbl_ramdump"
ANDROID="boot init_boot vendor_boot dtbo vbmeta vbmeta_system"
WANT="$LABELS"
for set in ${SETS//,/ }; do
    case "$set" in
        firmware) list="$FIRMWARE" ;;
        android) list="$ANDROID" ;;
        *) die "Unknown set: $set (firmware or android)" ;;
    esac
    for name in $list; do WANT="${WANT:+$WANT,}${name}_${SLOT}"; done
done

SEL="$COPY/restore_selected.xml"; VER="$COPY/restore_verify.xml"
LENIENT=()
[[ -z "$LABELS" ]] && LENIENT=(--lenient)   # a preset may name partitions this unit does not have
python3 "$SCRIPT_DIR/edl-gpt-to-xml.py" --select "$COPY/restore.xml" --labels "$WANT" --out "$SEL" --verify-out "$VER" "${LENIENT[@]}" \
    || die "Selection refused or incomplete (see above)"
info "To be written: $(grep -o 'label="[^"]*"' "$SEL" | cut -d'"' -f2 | tr '\n' ' ')"

# --- tools (same as edl-backup.sh) --------------------------------------------------------------
src="$TOOLS"
if [[ -f "$src" && "$src" == *.zip ]]; then
    dir="$COPY/tools"; mkdir -p "$dir"
    names="$(unzip -Z1 "$src" | grep -E '(^|/)(fh_loader|QSaharaServer|xbl_s_devprg_ns\.melf)$' || true)"
    while IFS= read -r n; do unzip -o -j -q "$src" "$n" -d "$dir"; done <<< "$names"
    chmod +x "$dir/fh_loader" "$dir/QSaharaServer"; src="$dir"
fi
[[ -d "$src" ]] || die "Give the flat build of the console with --tools <folder or zip>"
FH_LOADER="$(find "$src" -name fh_loader -type f | head -1)"
QSAHARA="$(find "$src" -name QSaharaServer -type f | head -1)"
PROGRAMMER="$(find "$src" \( -name 'xbl_s_devprg_ns.melf' -o -name 'prog_firehose_*' \) -type f | head -1)"
[[ -x "$FH_LOADER" && -x "$QSAHARA" && -f "$PROGRAMMER" ]] || die "fh_loader, QSaharaServer and the programmer are needed in $src"

if $DRY_RUN; then
    info "Dry run: would write the partitions listed in $SEL, then read them back and compare. Nothing was written."
    cat "$SEL" | grep -o 'filename="[^"]*" label="[^"]*"'
    exit 0
fi

command -v lsusb >/dev/null && { lsusb | grep -q '05c6:9008' || die "The console is not in EDL (no 05c6:9008)"; }
if [[ -z "$PORT" ]]; then for p in /dev/ttyUSB*; do [[ -e "$p" ]] && { PORT="$p"; break; }; done; fi
[[ -n "$PORT" && -w "$PORT" ]] || die "No usable /dev/ttyUSB* port (is the udev rule for 05c6:9008 in place?)"

if ! $ASSUME_YES; then
    warn "This WRITES to the console: $(grep -o 'label="[^"]*"' "$SEL" | cut -d'"' -f2 | tr '\n' ' ')"
    read -r -p "Type YES to go on: " answer
    [[ "$answer" == YES ]] || die "Cancelled, nothing was written"
fi

if ! $SKIP_LOAD; then
    info "Loading the programmer"
    timeout 90 "$QSAHARA" -p "$PORT" -s "13:$PROGRAMMER" || die "The programmer did not load: unplug, EDL again, retry"
fi

# fh_loader writes what it reads into the current folder, not into --search_path: run it from the copy.
fh() { ( cd "$COPY" && "$FH_LOADER" --noprompt --port="$PORT" --memoryname=UFS --search_path="$COPY" --zlpawarehost=1 "$@" ); }
info "Writing"
fh --sendxml="$SEL" | grep -E 'ERROR|Finished' | grep -v wake_lock || true
info "Reading back to compare"
rm -f "$COPY"/vf_*.bin
fh --convertprogram2read --sendxml="$VER" | grep -E 'ERROR|Finished' | grep -v wake_lock || true

bad=0
for f in $(grep -o 'filename="[^"]*"' "$SEL" | cut -d'"' -f2); do
    if cmp -s "$COPY/$f" "$COPY/vf_$f"; then ok "$f identical"; else warn "$f DIFFERS from the copy"; bad=1; fi
done
rm -f "$COPY"/vf_*.bin
(( bad == 0 )) || die "The verification failed: do not start the console. Put it in EDL again and write again, or ask for help."
ok "Written and verified. Unplug the cable and hold the power button until the console restarts."
