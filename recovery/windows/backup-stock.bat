@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem Back up the running stock ROM of an Ayaneo Pocket DS over adb, before flashing LineageOS.
rem Windows version of backup-stock.sh: same files, same SHA256SUMS, so restore-stock.bat and
rem restore-stock.sh both accept the copy. Needs root on the console (KernelSU / Magisk "su").
rem
rem   backup-stock.bat [output folder]
rem
rem adb.exe must be in the PATH or next to this file (Android SDK Platform-Tools).
rem Saves, for the ACTIVE slot only:
rem   raw partitions:     boot init_boot vendor_boot dtbo recovery vbmeta vbmeta_system
rem   logical partitions: system system_ext product vendor odm vendor_dlkm system_dlkm
rem plus the data unique to this console: persist modemst1 modemst2 fsg fsc

cd /d "%~dp0"
set "PATH=%~dp0;%PATH%"

where adb >nul 2>&1 || ( call :die "adb.exe not found. Put it next to this file or in the PATH (Android SDK Platform-Tools)." & exit /b 1 )

adb devices | findstr /r /c:"device$" >nul && goto :adb_ok
adb devices | findstr /c:"unauthorized" >nul && ( call :die "The console refuses this PC: accept the 'Allow USB debugging?' prompt on the console, then run this file again." & exit /b 1 )
call :die "No console found via adb. Enable USB debugging on the console. If it is on, Windows lacks the adb driver: right-click usb_driver\android_winusb.inf next to this file, Install, then unplug and plug the console again." & exit /b 1
:adb_ok

adb shell su -c true >nul 2>&1 || ( call :die "Root (su) is required on the console. Grant root to the shell in KernelSU / Magisk." & exit /b 1 )

set "PLAT="
for /f "delims=" %%a in ('adb shell getprop ro.board.platform') do set "PLAT=%%a"
if /i not "!PLAT!"=="kalama" ( call :die "This does not look like a Pocket DS (ro.board.platform = !PLAT!, expected kalama)." & exit /b 1 )

set "SLOT="
for /f "delims=" %%a in ('adb shell getprop ro.boot.slot_suffix') do set "SLOT=%%a"
if "!SLOT!"=="" ( call :die "Could not read the active slot." & exit /b 1 )

for /f "delims=" %%a in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "STAMP=%%a"
set "OUT=%~1"
if "!OUT!"=="" set "OUT=%~dp0stock-backup-!STAMP!"
if not exist "!OUT!" mkdir "!OUT!" || ( call :die "Cannot create !OUT!" & exit /b 1 )

echo [INFO] Backing up slot !SLOT! to !OUT!
echo [INFO] About 10 GB, it takes a few minutes. Do not unplug the cable.

for %%p in (boot init_boot vendor_boot dtbo recovery vbmeta vbmeta_system) do (
    call :dump "/dev/block/by-name/%%p!SLOT!" "%%p.img" || exit /b 1
)
for %%p in (system system_ext product vendor odm vendor_dlkm system_dlkm) do (
    call :dump "/dev/block/mapper/%%p!SLOT!" "%%p.img" || exit /b 1
)
for %%p in (persist modemst1 modemst2 fsg fsc) do (
    call :dump "/dev/block/by-name/%%p" "%%p.img" || exit /b 1
)

set "FP=" & set "KER="
for /f "delims=" %%a in ('adb shell getprop ro.build.fingerprint') do set "FP=%%a"
for /f "delims=" %%a in ('adb shell uname -r') do set "KER=%%a"
(
    echo slot=!SLOT!
    echo fingerprint=!FP!
    echo kernel=!KER!
    echo date=!STAMP!
) > "!OUT!\backup-info.txt"

echo [STEP] Checksums (SHA256SUMS)
rem Same format as sha256sum on Linux (lower case, two spaces, ./name, LF), so restore-stock.sh
rem can check this copy too.
powershell -NoProfile -Command "$d='!OUT!'; $l = Get-ChildItem -LiteralPath $d -Filter *.img | Sort-Object Name | ForEach-Object { (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLower() + '  ./' + $_.Name }; [IO.File]::WriteAllText((Join-Path $d 'SHA256SUMS'), (($l -join \"`n\") + \"`n\"))" || ( call :die "Could not write SHA256SUMS" & exit /b 1 )

echo.
echo [OK] Backup complete: !OUT!
echo [INFO] Copy it to a second disk and never share it: persist, modemst1/2, fsg and fsc are unique to this console.
pause
exit /b 0

:dump
echo [STEP] %~2
adb exec-out su -c "dd if=%~1 bs=4194304 2>/dev/null" > "!OUT!\%~2"
for %%F in ("!OUT!\%~2") do if %%~zF EQU 0 ( call :die "Empty dump for %~1" & exit /b 1 )
exit /b 0

:die
echo [ERROR] %~1 1>&2
pause
exit /b 1
