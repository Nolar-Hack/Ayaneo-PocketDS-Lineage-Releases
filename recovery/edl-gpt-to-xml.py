#!/usr/bin/env python3
"""Reads the partition tables (GPT) of the UFS units of the console, dumped by edl-backup.sh, and writes
the firehose XML that reads every partition (reads.xml) and the one that would write them back
(restore.xml). Nothing here talks to the console.

  edl-gpt-to-xml.py --gpt-dir <dir with gpt<lun>.bin> --reads reads.xml --restore restore.xml --table table.txt

A GPT file holds the first sectors of a LUN (protective MBR, header, entries): 4096-byte sectors.
"""
import argparse
import glob
import os
import re
import struct
import sys

SECTOR = 4096
# Android data of the user and the big logical partition: never part of the safety copy (the system
# is rebuilt from the image, the data is not recoverable by a firmware restore anyway).
SKIP_BY_DEFAULT = {"userdata", "super", "metadata"}
MAX_SECTORS_DEFAULT = (1 << 30) // SECTOR  # partitions above 1 GiB are skipped too


def parse_gpt(data):
    off = data.find(b"EFI PART")
    if off < 0:
        raise ValueError("no GPT header")
    head = data[off:off + 92]
    entries_lba, count, size = struct.unpack("<QII", head[72:88])
    base = entries_lba * SECTOR
    out = []
    for i in range(count):
        entry = data[base + i * size: base + (i + 1) * size]
        if len(entry) < size:
            raise ValueError("GPT entries cut short: dump more sectors")
        if entry[:16] == b"\0" * 16:
            continue
        first, last = struct.unpack("<QQ", entry[32:48])
        name = entry[56:128].decode("utf-16le").rstrip("\0")
        out.append((name, first, last - first + 1))
    return out


def attrs(lun, name, first, count, filename):
    return ('SECTOR_SIZE_IN_BYTES="%d" file_sector_offset="0" filename="%s" label="%s" '
            'num_partition_sectors="%d" partofsingleimage="false" physical_partition_number="%d" '
            'readbackverify="false" size_in_KB="%.1f" sparse="false" start_sector="%d"'
            % (SECTOR, filename, name, count, lun, count * SECTOR / 1024.0, first))


def check(xml, folder):
    bad = 0
    for line in open(xml):
        m = re.search(r'filename="([^"]+)".*num_partition_sectors="(\d+)"', line)
        if not m:
            continue
        path = os.path.join(folder, m.group(1))
        want = int(m.group(2)) * SECTOR
        have = os.path.getsize(path) if os.path.exists(path) else -1
        if have != want:
            print("BAD %s: %d bytes read, %d expected" % (m.group(1), have, want))
            bad += 1
    print("every partition read in full" if not bad else "%d files are missing or short" % bad)
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", nargs=2, metavar=("XML", "DIR"),
                    help="only check that every file of the XML is in DIR with its full size")
    ap.add_argument("--gpt-dir")
    ap.add_argument("--reads")
    ap.add_argument("--restore")
    ap.add_argument("--table")
    ap.add_argument("--include-large", action="store_true", help="also the partitions above 1 GiB")
    ap.add_argument("--skip", default="", help="more labels to leave out, comma separated")
    args = ap.parse_args()
    if args.check:
        sys.exit(check(*args.check))
    if not (args.gpt_dir and args.reads and args.restore and args.table):
        ap.error("--gpt-dir, --reads, --restore and --table are needed")
    skip = set(SKIP_BY_DEFAULT) | {s for s in args.skip.split(",") if s}

    reads, restores, table, total = [], [], [], 0
    files = sorted(glob.glob(os.path.join(args.gpt_dir, "gpt*.bin")))
    if not files:
        sys.exit("no gpt<lun>.bin in %s" % args.gpt_dir)
    for path in files:
        lun = int(re.search(r"gpt(\d+)\.bin$", path).group(1))
        try:
            parts = parse_gpt(open(path, "rb").read())
        except ValueError as e:
            print("LUN %d: %s (skipped)" % (lun, e), file=sys.stderr)
            continue
        for name, first, count in parts:
            kept = name not in skip and (args.include_large or count <= MAX_SECTORS_DEFAULT)
            table.append("lun%d %-24s start %-9d sectors %-9d %7.1f MB  %s"
                         % (lun, name, first, count, count * SECTOR / 1048576.0,
                            "read" if kept else "left out"))
            if not kept:
                continue
            fname = "lun%d_%s.bin" % (lun, name)
            reads.append("  <program %s/>" % attrs(lun, name, first, count, fname))
            restores.append("  <program %s/>" % attrs(lun, name, first, count, fname))
            total += count * SECTOR

    with open(args.reads, "w") as f:
        f.write('<?xml version="1.0" ?>\n<data>\n' + "\n".join(reads) + "\n</data>\n")
    with open(args.restore, "w") as f:
        f.write('<?xml version="1.0" ?>\n<data>\n' + "\n".join(restores) + "\n</data>\n")
    with open(args.table, "w") as f:
        f.write("\n".join(table) + "\n")
    print("%d partitions to read, %.2f GB" % (len(reads), total / 1e9))


if __name__ == "__main__":
    main()
