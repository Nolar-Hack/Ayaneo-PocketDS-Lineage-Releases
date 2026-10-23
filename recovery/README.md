# Safety copy of the console's firmware (EDL)

A copy of the firmware that starts your Pocket DS (the boot chain `xbl`, `abl`, `tz`, `hyp`, `aop`,
`modem`…), of its Android images and of the data that is unique to your unit (`persist`, the modem
calibration). Make it **once, before anything goes wrong**. If the console one day no longer starts at
all, that copy is what lets you bring it back.

> **Status: experimental.** The script reads the partition table the same way as the files that were used
> to recover a console, and its output was checked against those files, but it has **not yet been run on a
> console in EDL**. It only reads: it writes nothing to the console. If something looks wrong, stop and
> ask before going on.

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

Writing the partitions back is not automated here, on purpose: a wrong write can make things worse. The
steps that worked on the development console are in the
[install guide](https://claude.ai/artifact/DWn1DSxQ72MfHgZbC5ZeEJ), section *Disaster recovery with EDL*.
Read the whole section first and ask for help if you are not sure.
