#!/bin/bash
# Kompilasi SEMUA modul yang dibangun device tree A37 sekaligus.
#
# Alasannya ongkos: build penuh menabrak kesalahan API device tree satu per satu,
# masing-masing berbiaya sekitar 90 menit sampai titik gagalnya. Modul-modul ini
# hanya butuh beberapa menit dan memunculkan seluruh kelas kesalahan sekaligus.
#
# $(TARGET_BOARD_PLATFORM) = msm8916.
cd /root/los22 || exit 1
export LC_ALL=C
LOG=/root/los22/build-devmods.log
echo "mulai $(date '+%F %T')" > "$LOG"
source build/envsetup.sh >/dev/null 2>&1
lunch lineage_A37-bp1a-userdebug >/dev/null 2>&1
m -j10 \
  libshim_camera libcamera_shim libril_shim \
  libloc_eng libloc_core libloc_ds_api libloc_api_v02 libgps.utils \
  gps.msm8916 sensors.msm8916 camera.msm8916 power.msm8916 \
  libinit_msm8916 libwcnss_qmi dtbToolOppo \
  android.hardware.light@2.0-service.oppo_msm8916 \
  android.hardware.usb@1.0-service.cyanogen_8916 \
  >> "$LOG" 2>&1
echo "SELESAI rc=$? $(date '+%F %T')" >> "$LOG"
