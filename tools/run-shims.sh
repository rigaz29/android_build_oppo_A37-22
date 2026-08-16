#!/bin/bash
# Kompilasi hanya modul shim A37 -- jauh lebih murah daripada menunggu build
# penuh menabrak kesalahan API berikutnya 90 menit kemudian.
cd /root/los22 || exit 1
export LC_ALL=C
LOG=/root/los22/build-shims.log
echo "mulai $(date '+%F %T')" > "$LOG"
source build/envsetup.sh >/dev/null 2>&1
lunch lineage_A37-bp1a-userdebug >/dev/null 2>&1
m -j10 libshim_camera libcamera_shim libril_shim >> "$LOG" 2>&1
echo "SELESAI rc=$? $(date '+%F %T')" >> "$LOG"
