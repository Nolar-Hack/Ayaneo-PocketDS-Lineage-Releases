#!/usr/bin/env bash
set -euo pipefail

# Safety copy of the console's own firmware, read in EDL (Qualcomm Emergency Download).
#
# It READS every partition of the console (the boot chain xbl, abl, tz, hyp, aop, modem ..., the
# Android images, persist, the calibration data) and writes nothing to it, except for the
# programmer it loads into the console's memory for the session. Kept apart, the copy is what a
# disaster recovery needs when the console no longer starts at all.
#
#   edl-backup.sh --tools <flat build folder or zip> [--out <folder>] [--port /dev/ttyUSB0]
#                 [--include-large] [--skip label,label] [--skip-load] [--dry-run]
#
# Not copied: userdata, super and metadata (the data of the console, and the system that is
# installed again from an image), and any partition over 1 GiB unless --include-large.
#
# Put the console in EDL first: power it off, hold Vol+ and Vol- together and plug the USB cable.
# `lsusb` must show 05c6:9008. The tools come from the official flat build of the console
# (fh_loader, QSaharaServer and the firehose programmer xbl_s_devprg_ns.melf): give the folder or
# the zip with --tools and the script takes the three files it needs by itself.
#
# THE COPY HOLDS DATA THAT IS UNIQUE TO YOUR CONSOLE (persist, modem calibration): never share it.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR=""
TOOLS=""
PORT=""
INCLUDE_LARGE=false
SKIP=""
SKIP_LOAD=false
DRY_RUN=false
LUNS="0 1 2 3 4 5"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tools) TOOLS="$2"; shift ;;
        --out) OUT_DIR="$2"; shift ;;
        --port) PORT="$2"; shift ;;
        --include-large) INCLUDE_LARGE=true ;;
        --skip) SKIP="$2"; shift ;;
        --skip-load) SKIP_LOAD=true ;;
        --dry-run) DRY_RUN=true ;;
        -h|--help) sed -n 4,22p "$0"; exit 0 ;;
        *) die "Unknown option: $1" ;;
    esac
    shift
done

OUT_DIR="${OUT_DIR:-./edl-backup-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"          # absolute: fh_loader runs from inside it
[[ -n "$TOOLS" ]] && TOOLS="$(readlink -f "$TOOLS")"
run() { if $DRY_RUN; then echo "  would run: $*"; else "$@"; fi; }

# --- the three tools ---------------------------------------------------------------------------
# From a folder, or taken out of the zip of the flat build (only these three files are extracted).
find_tools() {
    local src="${1:-}" dir
    if [[ -z "$src" ]]; then
        for src in ./edl-tools "$SCRIPT_DIR/edl-tools"; do [[ -d "$src" ]] && break; src=""; done
    fi
    [[ -n "$src" ]] || die "Give the flat build of the console with --tools <folder or zip> (fh_loader, QSaharaServer, xbl_s_devprg_ns.melf)"
    if [[ -f "$src" && "$src" == *.zip ]]; then
        dir="$OUT_DIR/tools"
        info "Taking the three tools out of $(basename "$src")"
        mkdir -p "$dir"
        local names
        names="$(unzip -Z1 "$src" | grep -E '(^|/)(fh_loader|QSaharaServer|xbl_s_devprg_ns\.melf)$' || true)"
        [[ "$(echo "$names" | grep -c .)" -ge 3 ]] || die "$src does not hold fh_loader, QSaharaServer and xbl_s_devprg_ns.melf"
        while IFS= read -r n; do unzip -o -j -q "$src" "$n" -d "$dir"; done <<< "$names"
        chmod +x "$dir/fh_loader" "$dir/QSaharaServer"
        src="$dir"
    fi
    [[ -d "$src" ]] || die "$src is neither a folder nor a zip"
    FH_LOADER="$(find "$src" -name fh_loader -type f | head -1)"
    QSAHARA="$(find "$src" -name QSaharaServer -type f | head -1)"
    PROGRAMMER="$(find "$src" \( -name 'xbl_s_devprg_ns.melf' -o -name 'prog_firehose_*' \) -type f | head -1)"
    [[ -x "$FH_LOADER" && -x "$QSAHARA" && -f "$PROGRAMMER" ]] \
        || die "Missing in $src: fh_loader, QSaharaServer and/or the programmer (xbl_s_devprg_ns.melf)"
    ok "fh_loader, QSaharaServer and the programmer found"
}

find_tools "$TOOLS"
command -v python3 >/dev/null || die "python3 is needed"

# --- the console in EDL -------------------------------------------------------------------------
if ! $DRY_RUN; then
    command -v lsusb >/dev/null && { lsusb | grep -q '05c6:9008' \
        || die "The console is not in EDL (no 05c6:9008). Power off, hold Vol+ and Vol-, plug the USB cable."; }
    if [[ -z "$PORT" ]]; then
        for p in /dev/ttyUSB*; do [[ -e "$p" ]] && { PORT="$p"; break; }; done
    fi
    [[ -n "$PORT" ]] || die "No /dev/ttyUSB* port: is the console in EDL, and the udev rule for 05c6:9008 in place?"
    [[ -w "$PORT" ]] || die "$PORT is not writable for you (udev rule: SUBSYSTEM==\"tty\", ATTRS{idVendor}==\"05c6\", ATTRS{idProduct}==\"9008\", MODE=\"0666\")"
else
    PORT="${PORT:-/dev/ttyUSB0}"
fi
info "EDL port: $PORT"
info "Copy goes to: $OUT_DIR  (keep it on a second disk, and never share it)"
mkdir -p "$OUT_DIR"

# --- programmer ---------------------------------------------------------------------------------
if $SKIP_LOAD; then
    info "Programmer assumed to be loaded already (--skip-load)"
else
    info "Loading the programmer into the console (it stays in RAM, nothing is written to it)"
    # A second run of QSaharaServer in the same EDL session hangs: unplug, EDL again, start over.
    if ! $DRY_RUN; then
        timeout 90 "$QSAHARA" -p "$PORT" -s "13:$PROGRAMMER" || die "The programmer did not load. Unplug the cable, put the console in EDL again and retry."
    else
        run "$QSAHARA" -p "$PORT" -s "13:$PROGRAMMER"
    fi
fi

# fh_loader writes what it reads into the current folder, not into --search_path: run it from the copy.
fh() { ( cd "$OUT_DIR" && "$FH_LOADER" --noprompt --port="$PORT" --memoryname=UFS --search_path="$OUT_DIR" --zlpawarehost=1 "$@" ); }

# --- the partition tables ----------------------------------------------------------------------
info "Reading the partition table of each unit (LUN)"
GPT_XML="$OUT_DIR/gpt_reads.xml"
{
    echo '<?xml version="1.0" ?>'; echo '<data>'
    for lun in $LUNS; do
        echo "  <program SECTOR_SIZE_IN_BYTES=\"4096\" file_sector_offset=\"0\" filename=\"gpt${lun}.bin\" label=\"gpt${lun}\" num_partition_sectors=\"6\" partofsingleimage=\"false\" physical_partition_number=\"${lun}\" readbackverify=\"false\" size_in_KB=\"24.0\" sparse=\"false\" start_sector=\"0\"/>"
    done
    echo '</data>'
} > "$GPT_XML"
if $DRY_RUN; then echo "  would run: fh_loader --convertprogram2read --sendxml=$GPT_XML (from $OUT_DIR)"; else fh --convertprogram2read --sendxml="$GPT_XML"; fi

if $DRY_RUN; then
    info "Dry run: nothing more can be done without the console (the table of partitions is read from it)."
    exit 0
fi

for lun in $LUNS; do
    [[ -s "$OUT_DIR/gpt${lun}.bin" ]] || { warn "LUN $lun has no partition table (unit not present?): left out"; rm -f "$OUT_DIR/gpt${lun}.bin"; }
done
ARGS=(--gpt-dir "$OUT_DIR" --reads "$OUT_DIR/reads.xml" --restore "$OUT_DIR/restore.xml" --table "$OUT_DIR/partitions.txt")
$INCLUDE_LARGE && ARGS+=(--include-large)
[[ -n "$SKIP" ]] && ARGS+=(--skip "$SKIP")
python3 "$SCRIPT_DIR/edl-gpt-to-xml.py" "${ARGS[@]}"

# --- the read -----------------------------------------------------------------------------------
info "Reading the partitions (this takes a few minutes)"
fh --convertprogram2read --sendxml="$OUT_DIR/reads.xml" --showpercentagecomplete \
    | grep -E 'ERROR|Finished|percent files transferred' | grep -v wake_lock | tail -5 || true

info "Checking that every partition was read in full"
python3 "$SCRIPT_DIR/edl-gpt-to-xml.py" --check "$OUT_DIR/reads.xml" "$OUT_DIR" \
    || die "Some partitions are missing or short: read again (put the console in EDL again) before you trust this copy"

( cd "$OUT_DIR" && sha256sum lun*_*.bin gpt*.bin > SHA256SUMS )
{
    echo "EDL safety copy of the console, $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Tools: $(basename "$FH_LOADER"), $(basename "$QSAHARA"), $(basename "$PROGRAMMER")"
    echo
    echo "Files: lun<unit>_<partition>.bin (raw), gpt<unit>.bin (partition tables)"
    echo "restore.xml writes them back (firehose); partitions.txt lists them. Check with: sha256sum -c SHA256SUMS"
    echo "Never restore persist onto another console: it holds the calibration of this one."
} > "$OUT_DIR/README.txt"

ok "Safety copy complete: $OUT_DIR ($(du -sh "$OUT_DIR" | cut -f1))"
warn "Copy this folder to a second disk. It holds data unique to your console: do not publish it."
info "To leave EDL, unplug the cable and hold the power button until the console restarts."
