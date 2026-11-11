@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem Safety copy of the Pocket DS firmware, read in EDL (Qualcomm Emergency Download), for Windows.
rem Windows version of edl-backup.sh. It READS the partitions and writes nothing to the console
rem (the programmer only goes into its memory). Works on a stock console: no root needed.
rem
rem   edl-backup.bat <flat build zip, folder, or xbl_s_devprg_ns.melf> [output folder]
rem
rem Needs, next to this file: qdl\qdl.exe and its DLLs (github.com/linux-msm/qdl, release
rem qdl-binary-windows-x64). The programmer comes from the console's flat build from Ayaneo.
rem The console must be in EDL: powered off, hold Vol+ and Vol- together and plug the USB cable.
rem Driver: the Qualcomm "QDLoader 9008" driver, or WinUSB installed with Zadig.
rem
rem Left out: userdata, super, metadata and rawdump (your data, the system that a zip installs
rem again, and an empty dump area). THE COPY HOLDS DATA UNIQUE TO YOUR CONSOLE: never share it.
rem The list of partitions is the table of a Pocket DS (firmware 01.00_20261010), read by name.

cd /d "%~dp0"
set "QDL=%~dp0qdl\qdl.exe"
if not exist "!QDL!" ( call :die "qdl\qdl.exe not found next to this file (github.com/linux-msm/qdl, release qdl-binary-windows-x64)." & exit /b 1 )
set "SRC=%~f1"
if "!SRC!"=="" ( call :die "Usage: edl-backup.bat <flat build zip, folder, or xbl_s_devprg_ns.melf> [output folder]" & exit /b 1 )
if not exist "!SRC!" ( call :die "!SRC! not found." & exit /b 1 )

for /f "delims=" %%a in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd-HHmmss"') do set "STAMP=%%a"
set "OUT=%~f2"
if "!OUT!"=="" set "OUT=%~dp0edl-backup-!STAMP!"
if not exist "!OUT!" mkdir "!OUT!" || ( call :die "Cannot create !OUT!" & exit /b 1 )

rem --- the programmer: from a zip (only that file is taken out), a folder, or given directly ---
set "MELF=!OUT!\xbl_s_devprg_ns.melf"
if /i "%~x1"==".zip" (
    echo [INFO] Taking the programmer out of %~nx1
    powershell -NoProfile -Command "Add-Type -A System.IO.Compression.FileSystem; $z=[IO.Compression.ZipFile]::OpenRead('!SRC!'); $e=$z.Entries | Where-Object { $_.Name -eq 'xbl_s_devprg_ns.melf' } | Select-Object -First 1; if (-not $e) { exit 1 }; [IO.Compression.ZipFileExtensions]::ExtractToFile($e,'!MELF!',$true); $z.Dispose()" || ( call :die "xbl_s_devprg_ns.melf not found in %~nx1: is it the flat build of the Pocket DS?" & exit /b 1 )
) else if /i "%~x1"==".melf" (
    copy /y "!SRC!" "!MELF!" >nul
) else (
    set "FOUND="
    for /r "%~f1" %%f in (xbl_s_devprg_ns.melf) do if exist "%%f" if not defined FOUND set "FOUND=%%f"
    if not defined FOUND ( call :die "xbl_s_devprg_ns.melf not found in !SRC!" & exit /b 1 )
    copy /y "!FOUND!" "!MELF!" >nul
)
echo [OK] Programmer ready

echo.
echo [INFO] The console must be in EDL now: powered off, hold Vol+ and Vol- and plug the USB cable.
echo        The screen stays black. If qdl waits forever, the EDL driver is missing (see the guide).
echo [INFO] Copy goes to: !OUT!
echo [INFO] Reading about 100 partitions (about 4 GB, a few minutes). Do not unplug the cable.
echo.

set "R0=read 0/0+6 gpt0.bin read 1/0+6 gpt1.bin read 2/0+6 gpt2.bin read 3/0+6 gpt3.bin read 4/0+6 gpt4.bin read 5/0+6 gpt5.bin read 0/ssd lun0_ssd.bin read 0/persist lun0_persist.bin read 0/misc lun0_misc.bin read 0/keystore lun0_keystore.bin read 0/frp lun0_frp.bin read 0/vbmeta_system_a lun0_vbmeta_system_a.bin read 0/vbmeta_system_b lun0_vbmeta_system_b.bin read 1/xbl_a lun1_xbl_a.bin read 1/xbl_config_a lun1_xbl_config_a.bin read 1/multiimgqti_a lun1_multiimgqti_a.bin read 1/multiimgoem_a lun1_multiimgoem_a.bin read 1/apdp lun1_apdp.bin read 2/xbl_b lun2_xbl_b.bin read 2/xbl_config_b lun2_xbl_config_b.bin read 2/multiimgqti_b lun2_multiimgqti_b.bin read 2/multiimgoem_b lun2_multiimgoem_b.bin read 2/apdpb lun2_apdpb.bin read 3/ALIGN_TO_128K_1 lun3_ALIGN_TO_128K_1.bin read 3/cdt lun3_cdt.bin read 3/ddr lun3_ddr.bin read 4/uefi_a lun4_uefi_a.bin read 4/aop_a lun4_aop_a.bin read 4/aop_config_a lun4_aop_config_a.bin read 4/tz_a lun4_tz_a.bin read 4/hyp_a lun4_hyp_a.bin read 4/modem_a lun4_modem_a.bin read 4/bluetooth_a lun4_bluetooth_a.bin read 4/mdtpsecapp_a lun4_mdtpsecapp_a.bin read 4/mdtp_a lun4_mdtp_a.bin read 4/abl_a lun4_abl_a.bin read 4/dsp_a lun4_dsp_a.bin read 4/keymaster_a lun4_keymaster_a.bin read 4/boot_a lun4_boot_a.bin read 4/devcfg_a lun4_devcfg_a.bin read 4/qupfw_a lun4_qupfw_a.bin read 4/vbmeta_a lun4_vbmeta_a.bin read 4/dtbo_a lun4_dtbo_a.bin read 4/uefisecapp_a lun4_uefisecapp_a.bin read 4/imagefv_a lun4_imagefv_a.bin read 4/shrm_a lun4_shrm_a.bin"
set "R1=read 4/vm-bootsys_a lun4_vm-bootsys_a.bin read 4/cpucp_a lun4_cpucp_a.bin read 4/featenabler_a lun4_featenabler_a.bin read 4/vendor_boot_a lun4_vendor_boot_a.bin read 4/qmcs lun4_qmcs.bin read 4/qweslicstore_a lun4_qweslicstore_a.bin read 4/recovery_a lun4_recovery_a.bin read 4/xbl_ramdump_a lun4_xbl_ramdump_a.bin read 4/rticmpdata_a lun4_rticmpdata_a.bin read 4/init_boot_a lun4_init_boot_a.bin read 4/uefi_b lun4_uefi_b.bin read 4/aop_b lun4_aop_b.bin read 4/aop_config_b lun4_aop_config_b.bin read 4/tz_b lun4_tz_b.bin read 4/hyp_b lun4_hyp_b.bin read 4/modem_b lun4_modem_b.bin read 4/bluetooth_b lun4_bluetooth_b.bin read 4/mdtpsecapp_b lun4_mdtpsecapp_b.bin read 4/mdtp_b lun4_mdtp_b.bin read 4/abl_b lun4_abl_b.bin read 4/dsp_b lun4_dsp_b.bin read 4/keymaster_b lun4_keymaster_b.bin read 4/boot_b lun4_boot_b.bin read 4/devcfg_b lun4_devcfg_b.bin read 4/qupfw_b lun4_qupfw_b.bin read 4/vbmeta_b lun4_vbmeta_b.bin read 4/dtbo_b lun4_dtbo_b.bin read 4/uefisecapp_b lun4_uefisecapp_b.bin read 4/imagefv_b lun4_imagefv_b.bin read 4/shrm_b lun4_shrm_b.bin read 4/vm-bootsys_b lun4_vm-bootsys_b.bin read 4/cpucp_b lun4_cpucp_b.bin read 4/featenabler_b lun4_featenabler_b.bin read 4/vendor_boot_b lun4_vendor_boot_b.bin read 4/qweslicstore_b lun4_qweslicstore_b.bin read 4/recovery_b lun4_recovery_b.bin read 4/xbl_ramdump_b lun4_xbl_ramdump_b.bin read 4/rticmpdata_b lun4_rticmpdata_b.bin read 4/init_boot_b lun4_init_boot_b.bin read 4/devinfo lun4_devinfo.bin read 4/dip lun4_dip.bin"
set "R2=read 4/splash lun4_splash.bin read 4/limits lun4_limits.bin read 4/limits-cdsp lun4_limits-cdsp.bin read 4/toolsfv lun4_toolsfv.bin read 4/logfs lun4_logfs.bin read 4/logdump lun4_logdump.bin read 4/storsec lun4_storsec.bin read 4/uefivarstore lun4_uefivarstore.bin read 4/secdata lun4_secdata.bin read 4/vm-data lun4_vm-data.bin read 4/vm-persist lun4_vm-persist.bin read 4/mdcompress lun4_mdcompress.bin read 4/connsec lun4_connsec.bin read 4/tzsc lun4_tzsc.bin read 4/spunvm lun4_spunvm.bin read 4/xbl_sc_test_mode lun4_xbl_sc_test_mode.bin read 4/xbl_sc_logs lun4_xbl_sc_logs.bin read 5/ALIGN_TO_128K_2 lun5_ALIGN_TO_128K_2.bin read 5/modemst1 lun5_modemst1.bin read 5/modemst2 lun5_modemst2.bin read 5/fsg lun5_fsg.bin read 5/fsc lun5_fsc.bin"

pushd "!OUT!"
"!QDL!" --storage ufs "!MELF!" !R0! !R1! !R2!
set "RC=!errorlevel!"
popd
if not "!RC!"=="0" ( call :die "qdl stopped with an error (code !RC!). Unplug the cable, put the console in EDL again and run this file again." & exit /b 1 )

echo [STEP] Checking that every partition was read in full
set "Z0=gpt0.bin=24576;gpt1.bin=24576;gpt2.bin=24576;gpt3.bin=24576;gpt4.bin=24576;gpt5.bin=24576;lun0_ssd.bin=8192;lun0_persist.bin=33554432;lun0_misc.bin=1048576;lun0_keystore.bin=524288;lun0_frp.bin=524288;lun0_vbmeta_system_a.bin=65536;lun0_vbmeta_system_b.bin=65536;lun1_xbl_a.bin=3670016;lun1_xbl_config_a.bin=307200;lun1_multiimgqti_a.bin=32768;lun1_multiimgoem_a.bin=32768;lun1_apdp.bin=262144;lun2_xbl_b.bin=3670016;lun2_xbl_config_b.bin=307200;lun2_multiimgqti_b.bin=32768;lun2_multiimgoem_b.bin=32768;lun2_apdpb.bin=262144;lun3_ALIGN_TO_128K_1.bin=106496;lun3_cdt.bin=131072;lun3_ddr.bin=1048576;lun4_uefi_a.bin=5242880;lun4_aop_a.bin=524288;lun4_aop_config_a.bin=524288;lun4_tz_a.bin=4194304;lun4_hyp_a.bin=8388608;lun4_modem_a.bin=335544320;lun4_bluetooth_a.bin=6291456;lun4_mdtpsecapp_a.bin=4194304;lun4_mdtp_a.bin=33554432;lun4_abl_a.bin=1048576;lun4_dsp_a.bin=67108864;lun4_keymaster_a.bin=524288;lun4_boot_a.bin=100663296;lun4_devcfg_a.bin=131072;lun4_qupfw_a.bin=81920;lun4_vbmeta_a.bin=65536;lun4_dtbo_a.bin=25165824;lun4_uefisecapp_a.bin=2097152;lun4_imagefv_a.bin=2097152;lun4_shrm_a.bin=131072;lun4_vm-bootsys_a.bin=563200000;lun4_cpucp_a.bin=1048576;lun4_featenabler_a.bin=131072;lun4_vendor_boot_a.bin=100663296;lun4_qmcs.bin=31457280;lun4_qweslicstore_a.bin=262144;lun4_recovery_a.bin=104857600;lun4_xbl_ramdump_a.bin=2097152;lun4_rticmpdata_a.bin=53248;lun4_init_boot_a.bin=8388608;lun4_uefi_b.bin=5242880;lun4_aop_b.bin=524288;lun4_aop_config_b.bin=524288;lun4_tz_b.bin=4194304;lun"
set "Z1=4_hyp_b.bin=8388608;lun4_modem_b.bin=335544320;lun4_bluetooth_b.bin=6291456;lun4_mdtpsecapp_b.bin=4194304;lun4_mdtp_b.bin=33554432;lun4_abl_b.bin=1048576;lun4_dsp_b.bin=67108864;lun4_keymaster_b.bin=524288;lun4_boot_b.bin=100663296;lun4_devcfg_b.bin=131072;lun4_qupfw_b.bin=81920;lun4_vbmeta_b.bin=65536;lun4_dtbo_b.bin=25165824;lun4_uefisecapp_b.bin=2097152;lun4_imagefv_b.bin=2097152;lun4_shrm_b.bin=131072;lun4_vm-bootsys_b.bin=563200000;lun4_cpucp_b.bin=1048576;lun4_featenabler_b.bin=131072;lun4_vendor_boot_b.bin=100663296;lun4_qweslicstore_b.bin=262144;lun4_recovery_b.bin=104857600;lun4_xbl_ramdump_b.bin=2097152;lun4_rticmpdata_b.bin=53248;lun4_init_boot_b.bin=8388608;lun4_devinfo.bin=4096;lun4_dip.bin=1048576;lun4_splash.bin=34226176;lun4_limits.bin=4096;lun4_limits-cdsp.bin=4096;lun4_toolsfv.bin=1048576;lun4_logfs.bin=8388608;lun4_logdump.bin=536870912;lun4_storsec.bin=131072;lun4_uefivarstore.bin=524288;lun4_secdata.bin=28672;lun4_vm-data.bin=34226176;lun4_vm-persist.bin=125829120;lun4_mdcompress.bin=20971520;lun4_connsec.bin=131072;lun4_tzsc.bin=131072;lun4_spunvm.bin=33554432;lun4_xbl_sc_test_mode.bin=65536;lun4_xbl_sc_logs.bin=131072;lun5_ALIGN_TO_128K_2.bin=106496;lun5_modemst1.bin=3145728;lun5_modemst2.bin=3145728;lun5_fsg.bin=3145728;lun5_fsc.bin=131072"
set "SIZES=!Z0!!Z1!"
powershell -NoProfile -Command "$d='!OUT!'; $bad=0; foreach ($p in $env:SIZES.Split(';')) { $n,$s=$p.Split('='); $f=Join-Path $d $n; if (-not (Test-Path -LiteralPath $f) -or (Get-Item -LiteralPath $f).Length -ne [int64]$s) { Write-Host \"  missing or short: $n\"; $bad++ } }; exit $bad" || ( call :die "Some partitions are missing or short: put the console in EDL again and run this file again before you trust this copy." & exit /b 1 )

echo [STEP] Checksums (SHA256SUMS)
powershell -NoProfile -Command "$d='!OUT!'; $l = Get-ChildItem -LiteralPath $d -File | Where-Object { $_.Name -like 'lun*_*.bin' -or $_.Name -like 'gpt*.bin' } | Sort-Object Name | ForEach-Object { (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLower() + '  ' + $_.Name }; [IO.File]::WriteAllText((Join-Path $d 'SHA256SUMS'), (($l -join \"`n\") + \"`n\"))" || ( call :die "Could not write SHA256SUMS" & exit /b 1 )
del "!MELF!" >nul 2>&1

echo.
echo [OK] Safety copy complete: !OUT!
echo [WARN] Copy this folder to a second disk. It holds data unique to your console: never share it.
echo [INFO] To leave EDL, unplug the cable and hold the power button until the console restarts.
pause
exit /b 0

:die
echo [ERROR] %~1 1>&2
pause
exit /b 1
