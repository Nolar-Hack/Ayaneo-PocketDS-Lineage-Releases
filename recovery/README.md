# Before you install, and if something goes wrong

Helper scripts for the install guide. Get them with `git clone https://github.com/Nolar-Hack/Ayaneo-PocketDS-Lineage-Releases`,
then open the `recovery` folder.

| Script | What it does |
|---|---|
| `backup-stock.sh` | Copies your stock Android system, partition by partition, over `adb` (needs root on the stock system). Run it **before installing**. |
| `restore-stock.sh <copy folder>` | Puts that stock system back, from fastbootd. It wipes your data. |
| `edl-backup.sh` | Read-only copy of the firmware that starts the console, in EDL (below). Run it before installing too. |
| `edl-restore.sh` | Writes chosen firmware partitions back from that copy, for a console that no longer starts. |

```
./backup-stock.sh                 # needs the console running its stock system, adb connected, su available
```
Keep every copy on a second disk and never share them: they hold data that is unique to your console.

---

# Safety copy of the console's firmware (EDL)

A copy of the firmware that starts your Pocket DS (the boot chain `xbl`, `abl`, `tz`, `hyp`, `aop`,
`modem`…), of its Android images and of the data that is unique to your unit (`persist`, the modem
calibration). Make it **once, before anything goes wrong**. If the console one day no longer starts at
all, that copy is what lets you bring it back.

> **Status.** `edl-backup.sh` was run on a Pocket DS in EDL (2026-10-23): 103 partitions, 3.9 GB, read in about two
> minutes, every file checked for its full size and with matching checksums. Several firmware partitions came out
> identical to dumps taken earlier from the same console. It only reads: it writes nothing to the console.
> `edl-restore.sh` has **not been run on a console yet**: use its `--dry-run` first.

## What you need

- A Linux PC with `python3`, `unzip` and `lsusb`.
- The **flat build of the console** from Ayaneo (a zip of about 4 GB). Only three files of it are used:
  `fh_loader`, `QSaharaServer` and `xbl_s_devprg_ns.melf`. They belong to Qualcomm and Ayaneo and are not
  included here. Give the script the zip (or the folder it was unzipped to) and it takes the three files out
  by itself.
- A udev rule so that your user can open the console in EDL (`/etc/udev/rules.d/99-qdl.rules`):
  ```
  SUBSYSTEM=="tty", ATTRS{idVendor}=="05c6", ATTRS{idProduct}=="9008", MODE="0666"
  ```
- 5 GB of free space for the copy, on a disk you will keep.

## Make the copy

1. **Put the console in EDL.** Power it off, hold **Vol+** and **Vol−** together and plug the USB cable into
   the PC. The screen stays black. `lsusb` must show `05c6:9008`.
2. Run (the dry run first shows what it would do and writes nothing):
   ```
   ./edl-backup.sh --tools ~/Downloads/AR11_FlatBuild_….zip --dry-run
   ./edl-backup.sh --tools ~/Downloads/AR11_FlatBuild_….zip
   ```
3. Wait a few minutes. The script reads every partition, checks that each one was read in full and writes
   `SHA256SUMS`.
4. **Unplug the cable** and hold the power button until the console restarts.
5. **Copy the folder to a second disk.**

If the programmer does not load (the script says so), unplug the cable, put the console in EDL again and
start over. Do not run the loading step twice in the same EDL session: it hangs.

## What is in the copy

`lun<unit>_<partition>.bin` for each partition (raw), `gpt<unit>.bin` (the partition tables),
`partitions.txt` (the list), `reads.xml` and `restore.xml` (the firehose files that read and would write
them), `SHA256SUMS` and a short `README.txt`.

Left out on purpose: `userdata`, `super` and `metadata` (your data, and the system, which is installed
again from an image) and any partition above 1 GiB (`--include-large` adds them).

## Keep it private

The copy holds data **that is unique to your console** (`persist`, `modemst1`, `modemst2`, `fsg`, `fsc`,
the unlock state `devinfo`). Do not post it or give it to anyone. Another person must never write your
`persist` onto their console.

## Using it for a recovery

When the console no longer starts, put it in EDL again and write back **only what is broken**, from your own copy.
`edl-restore.sh` writes the partitions you choose, then reads them back and compares them with the copy; it stops
at the first difference. It checks `SHA256SUMS` first, and it never writes `persist`, the modem calibration,
`devinfo`, `xbl`, the partition tables or your data.

```
# what would be written (nothing is written)
./edl-restore.sh --tools ~/Downloads/AR11_FlatBuild_….zip --copy ./edl-backup-… --slot a --set firmware --dry-run
# the firmware of slot a
./edl-restore.sh --tools ~/Downloads/AR11_FlatBuild_….zip --copy ./edl-backup-… --slot a --set firmware
# if it still does not start: the Android images of that slot
./edl-restore.sh --tools ~/Downloads/AR11_FlatBuild_….zip --copy ./edl-backup-… --slot a --set android
```

`--slot` is the slot that is broken (the one that was active). Do not restore a slot that works. `--labels abl_a,tz_a`
writes exact partitions. The steps and the cases are in the
[install guide](https://claude.ai/artifact/DWn1DSxQ72MfHgZbC5ZeEJ), *Troubleshooting → If the console no longer starts at all*.

> The restore script has **not been run on a console yet**. The firmware list it writes is the one that brought the
> development console back, and the write is verified before you start the console.
