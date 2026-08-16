#!/bin/bash
# Pemeriksaan fungsi setelah A37 berhasil boot ke homescreen.
# Dijalankan di mesin yang tercolok perangkat, BUKAN di mesin build.
#
#   bash cek-fungsi.sh > hasil-cek.txt 2>&1
#
# Tiap blok terikat ke risiko yang sudah tercatat di proyek ini, bukan daftar
# umum. Kolom "kenapa" menjelaskan asal kecurigaannya.

adb wait-for-device

j() { printf '\n=== %s ===\n' "$1"; }

j "identitas — pastikan yang teruji memang build ini"
adb shell getprop ro.lineage.version
adb shell getprop ro.build.version.release
adb shell getprop ro.build.date.utc
adb shell getprop ro.lineage.device
adb shell getprop ro.build.product

j "tiga akar yang sudah diperbaiki — tidak boleh kambuh"
# boot 1: rename() -> renameat2 ENOSYS, classpath tidak pernah terbentuk
adb shell ls -l /data/system/environ/
# boot 2: netd abort di BpfHandler::init
adb shell getprop init.svc.netd
# boot 3: system_server abort di JNI ClatCoordinator
adb shell 'logcat -d | grep -c ">>> system_server <<<"'
adb shell getprop sys.boot_completed

j "composer — crash di boot 2 DAN boot 3, dua-duanya pulih sendiri"
# Kalau berubah jadi crash-loop, akarnya IdleInvalidator (libqdutils):
# turunan RefBase dipegang static sp<> sementara getInstance() balikkan pointer mentah.
adb shell getprop init.svc.vendor.hwcomposer-2-1
adb shell getprop init.svc.surfaceflinger
adb shell 'logcat -d | grep -icE "IdleInvalidator|Double owned"'

j "tethering — com.android.tethering.inprocess DICABUT di Android 15"
# Di LOS 21 mekanisme itulah yang memperbaiki SecurityException
# MAINLINE_NETWORK_STACK. Di 22 sudah tidak ada, dan penggantinya belum diketahui.
# Gejala khas kalau kambuh: Settings tampil putih polos tanpa toolbar, Back mati.
adb shell 'logcat -d | grep -i "Networking module does not have permission"'
adb shell 'logcat -d | grep -ic tethering'
adb shell dumpsys connectivity | head -20

j "bluetooth — di LOS 21 servis qti crash-loop tiap 5 detik"
adb shell getprop init.svc.vendor.bluetooth-1-0-qti
adb shell getprop bluetooth.enabled
adb shell 'logcat -d | grep -icE "bluetooth.*(crash|died|restart)"'

j "wifi dan RIL — terbukti jalan di LOS 20, belum diuji di 22"
adb shell getprop init.svc.wpa_supplicant
adb shell getprop wifi.interface
adb shell getprop gsm.sim.state
adb shell getprop gsm.network.type
adb shell getprop init.svc.vendor.ril-daemon

j "akibat BPF-less yang DIHARAPKAN — ini bukan bug, catat saja apa adanya"
# Perangkat tidak punya CONFIG_BPF_SYSCALL. Tiga penjaga yang dipasang membuat
# boot lewat, tapi fitur yang memang bersandar pada eBPF tetap tidak berfungsi:
#   - statistik pemakaian data per aplikasi (BpfNetMaps terdegradasi)
#   - 464XLAT / clat (verifikasi BPF-nya dilewati)
#   - tethering offload
# Yang perlu dipastikan: ketiadaannya tidak MENJATUHKAN apa pun.
adb shell ls -l /sys/fs/bpf/ 2>&1 | head -3
adb shell dumpsys netstats --uid 2>&1 | head -8
adb shell 'logcat -d | grep -icE "BpfMap|bpf.*(fail|error)"'

j "storaged — DIKETAHUI kosong, sysfs_disk_stat dicabut demi uji beku sepolicy"
adb shell dumpsys storaged 2>&1 | head -5

j "kandidat audit yang belum pernah teruji sampai boot 3"
# Kelima ini muncul sebagai ABSEN di tools/audit-kit21.sh dan sengaja ditahan
# karena boot selalu mati sebelum sempat menjalankannya.
adb shell 'logcat -d | grep -icE "freezer|cgroup"'
adb shell 'logcat -d | grep -icE "SensorPrivacy"'
adb shell 'logcat -d | grep -icE "ConsumerIr|IR HAL"'
adb shell 'logcat -d | grep -c "createProcessGroup.*failed"'

j "kesehatan umum — proses yang mati berulang"
adb shell 'logcat -d | grep -oE ">>> [^ ]+ <<<" | sort | uniq -c | sort -rn | head'
adb shell 'logcat -d | grep -c "avc:  denied"'
adb shell dumpsys activity processes 2>&1 | grep -c ProcessRecord

j "stabilitas — servis yang restarting"
adb shell 'getprop | grep "init\.svc\." | grep -v ": \[running\]" | grep -v ": \[stopped\]"'
