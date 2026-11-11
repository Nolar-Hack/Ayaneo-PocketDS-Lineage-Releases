# Before you install, on Windows

The same copies as the Linux scripts of the [recovery](../) folder, from a Windows PC. Double-click a `.bat`, or run it
from a command prompt in this folder. **Copy this whole folder to your PC first** (for example `C:\PocketDS`): the copies
are written next to the scripts.

| Script | Root needed | What it does |
|---|---|---|
| `edl-backup.bat` | **no** | Safety copy of the whole console, read in EDL: the firmware that starts it, the Android images and the data unique to your unit. **Works on a console that was never modified.** Make this one. |
| `backup-stock.bat` | yes (KernelSU / Magisk) | Copy of the running stock system over adb, partition by partition. Only if you already rooted the stock system. |
| `restore-stock.bat <copy folder>` | - | Puts a `backup-stock` copy back, from fastbootd. **It wipes your data.** |

> **Status.** Run on a Pocket DS from a Windows 11 virtual machine (2026-11-11). `edl-backup.bat` read 109 partitions
> and tables: the firmware came out identical to a copy made on Linux, byte for byte. `backup-stock.bat` read 19 partitions,
> identical to the console. `restore-stock.bat` has **not** been run (it writes the console).

## The copy you need: `edl-backup.bat` (no root)

What the stock system cannot give back from Ayaneo's download page is the data unique to your console (`persist`,
the calibration). EDL reads it without root and without writing anything to the console: the programmer only goes into
its memory for the session.

### Once

1. **The flat build of the console** from Ayaneo (`AR11_FlatBuild_….zip`, about 4 GB) from
   https://www.ayaneo.com/support/download. The script only takes the programmer `xbl_s_devprg_ns.melf` out of it.
2. **The EDL driver.** Download **Zadig** from https://zadig.akeo.ie. Put the console in EDL (below), start Zadig, then
   *Options → List All Devices*, pick **QUSB_BULK…** (the USB ID must read `05C6 9008`), keep **WinUSB** and click
   **Install Driver**. This takes a minute or two.

### Each copy

1. **Put the console in EDL**: power it off, hold **Vol+** and **Vol−** together and plug the USB cable. The screen
   stays black.
2. **Drag the zip onto `edl-backup.bat`**, or run it with the path of the zip:
   ```
   edl-backup.bat "C:\Users\you\Downloads\AR11_FlatBuild_TurboX_C8550_xx.xx_LA1.0.D.user.20251012.065902.zip"
   ```
3. Wait a few minutes (about 4 GB). It checks that every partition was read in full and writes `SHA256SUMS`.
4. **Unplug the cable** and hold the power button until the console restarts.
5. **Copy the `edl-backup-<date>` folder to a second disk.**

If it stays on *Waiting for EDL device*, the driver is missing (Zadig, above). If it stops with an error, unplug,
put the console in EDL again and run it again: the programmer can only be sent once per EDL session.

The list of partitions it reads is the table of a Pocket DS with firmware 01.00_20261010. Left out: `userdata`, `super`,
`metadata` and `rawdump` (your data, the system that the install zip writes again, and an empty dump area).

## `backup-stock.bat` and `restore-stock.bat` (adb)

1. Download the **Android SDK Platform-Tools for Windows** from
   https://developer.android.com/tools/releases/platform-tools and put `adb.exe`, `fastboot.exe` and their DLLs in
   this folder (or in your PATH).
2. Install the **Google USB Driver** from https://developer.android.com/studio/run/win-usb: right-click
   `android_winusb.inf` → *Install*. If Windows still shows the console with a yellow triangle in the Device Manager,
   *Update driver* → *Browse* → the `usb_driver` folder → **Android ADB Interface**.
3. On the console: Developer options → **USB debugging** on, and accept *Allow USB debugging?* when the PC asks.
4. `backup-stock.bat` needs root on the console (KernelSU / Magisk: grant it to the shell). It writes a
   `stock-backup-<date>` folder, in the same format as `backup-stock.sh` (both restore scripts accept it).

## Keep it private

Both copies hold data **unique to your console** (`persist`, the calibration, the unlock state `devinfo`). Keep them
on a second disk, never post them and never write another console's `persist` onto yours.

## Third-party files

`qdl/` is [qdl](https://github.com/linux-msm/qdl) v2.9.1 by Linaro, the release binary `qdl-binary-windows-x64`
unchanged (BSD-3-Clause, see `qdl/LICENSE-qdl.txt`; its DLLs keep their own licenses: libusb and libiconv LGPL,
libxml2 MIT, libzip, zstd and zlib BSD-style). It is an open source replacement for Qualcomm's QSaharaServer and
fh_loader.
