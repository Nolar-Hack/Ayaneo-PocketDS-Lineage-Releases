@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem Puts back a copy made by backup-stock.bat (or backup-stock.sh), from fastbootd.
rem Windows version of restore-stock.sh. It WIPES the data of the console.
rem persist, modemst1/2, fsg and fsc are NOT written: they stay in the copy for a disaster recovery.
rem
rem   restore-stock.bat <copy folder>
rem
rem adb.exe and fastboot.exe must be in the PATH or next to this file (Android SDK Platform-Tools).

cd /d "%~dp0"
set "PATH=%~dp0;%PATH%"
set "B=%~1"
if "!B!"=="" ( call :die "Usage: restore-stock.bat <copy folder>" & exit /b 1 )
if not exist "!B!\SHA256SUMS" ( call :die "!B!\SHA256SUMS not found: is this a copy made by backup-stock?" & exit /b 1 )
where fastboot >nul 2>&1 || ( call :die "fastboot.exe not found (Android SDK Platform-Tools)." & exit /b 1 )

echo [STEP] Checking the copy (SHA256SUMS)
powershell -NoProfile -Command "$d='!B!'; $bad=0; Get-Content -LiteralPath (Join-Path $d 'SHA256SUMS') | Where-Object { $_ } | ForEach-Object { $h,$n = $_ -split '\s+',2; $n = $n -replace '^\*?\./',''; $f = Join-Path $d $n; if (-not (Test-Path -LiteralPath $f) -or (Get-FileHash -Algorithm SHA256 -LiteralPath $f).Hash.ToLower() -ne $h.ToLower()) { Write-Host \"  BAD: $n\"; $bad++ } }; exit $bad" || ( call :die "Backup checksum mismatch: do not restore this copy." & exit /b 1 )

echo.
echo [WARN] This restores the stock ROM on the CURRENT slot and WIPES the data of the console.
set /p "R=Continue? [y/N] "
if /i not "!R!"=="y" ( call :die "Aborted" & exit /b 1 )

rem The bootloader fastboot of the Pocket DS refuses "flash": go to fastbootd.
adb devices 2>nul | findstr /r /c:"device$" >nul && adb reboot fastboot
echo [INFO] Waiting for fastboot... (if nothing happens, install the Google USB driver for the console)
call :waitfb
fastboot getvar is-userspace 2>&1 | findstr /c:"is-userspace: yes" >nul
if errorlevel 1 (
    fastboot reboot fastboot
    timeout /t 5 /nobreak >nul
    call :waitfb
)
fastboot getvar is-userspace 2>&1 | findstr /c:"is-userspace: yes" >nul || ( call :die "The console did not enter fastbootd." & exit /b 1 )

fastboot snapshot-update cancel

for %%p in (vbmeta vbmeta_system boot init_boot vendor_boot dtbo recovery system system_ext product vendor odm vendor_dlkm system_dlkm) do (
    echo [STEP] Flashing %%p
    fastboot flash %%p "!B!\%%p.img" || ( call :die "Flashing %%p failed. Do not restart: ask for help with the message above." & exit /b 1 )
)

echo [STEP] Wiping userdata + metadata
fastboot -w

rem fastbootd on this console does not flush its writes before restarting: wait for them, or the
rem last images written are lost.
echo [STEP] Waiting 90 s for the writes to reach the storage. Do not unplug.
timeout /t 90 /nobreak >nul
fastboot reboot

echo [OK] Stock ROM restored.
pause
exit /b 0

:waitfb
fastboot devices 2>nul | findstr /c:"fastboot" >nul && exit /b 0
timeout /t 1 /nobreak >nul
goto waitfb

:die
echo [ERROR] %~1 1>&2
pause
exit /b 1
