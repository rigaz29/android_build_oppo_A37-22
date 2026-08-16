#!/bin/bash
# Bangun SELURUH modul di tiga HAL CAF msm8916 sekaligus.
#
# Ini "pekerjaan sungguhan" yang PLAN-LOS22.md 5.2a prediksikan: kode ini
# berasal dari LineageOS-UL lineage-21.0-caf-msm8916 (siap Android 14) dan harus
# di-forward-port ke Android 15. Menemukan galatnya lewat build penuh berbiaya
# sekitar 90 menit per instans; target semu MODULES-IN-* membangun semuanya
# dalam hitungan menit.
cd /root/los22 || exit 1
export LC_ALL=C
LOG=/root/los22/build-cafhal.log
echo "mulai $(date '+%F %T')" > "$LOG"
source build/envsetup.sh >/dev/null 2>&1
lunch lineage_A37-bp1a-userdebug >/dev/null 2>&1
m -j10 -k \
  MODULES-IN-hardware-qcom-caf-msm8916-audio \
  MODULES-IN-hardware-qcom-caf-msm8916-display \
  MODULES-IN-hardware-qcom-caf-msm8916-media \
  >> "$LOG" 2>&1
echo "SELESAI rc=$? $(date '+%F %T')" >> "$LOG"
