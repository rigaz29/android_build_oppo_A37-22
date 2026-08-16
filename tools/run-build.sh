#!/bin/bash
# Fase 4 - build ROM LineageOS 22.2 untuk OPPO A37.
#
# Dijalankan terlepas dari sesi: build penuh butuh berjam-jam sedangkan
# background task sesi diputus sekitar 11 menit.
#
# Parameter disamakan dengan titik yang TERBUKTI LOLOS di mesin ini, dicatat di
# android_build_oppo_A37-21/PLAN-ATTEMPT-OFFICIAL.md:789-792
#
#   -j10, swap 16 GB, swappiness 10   ninja OOM-killed di 44%
#   -j10, swap 32 GB, swappiness 60   LOLOS fase Java (swap terpakai 18 GB)   <- ini
#   -j6,  swap 10 GB                  soong_build OOM 2x
#   -j6,  swap 16 GB                  LOLOS
#
# Karena itu swap dinaikkan ke 31 GB dan swappiness ke 60 sebelum build.
#
# 16 Agustus 2026: turun ke -j6 atas permintaan, setelah soong_build kena OOM
# killer (anon-rss 9,3 GB di mesin 11 GB). Titik -j6 sudah tercatat LOLOS di
# tabel di atas, dan soong bootstrap memang fase paling haus memori.

cd /root/los22 || exit 1
export LC_ALL=C
export USE_CCACHE=1
export CCACHE_DIR=/root/.ccache
export CCACHE_EXEC=/usr/bin/ccache

LOG=/root/los22/build-fase4.log
{
  echo "mulai   $(date '+%F %T')"
  echo "mem     $(free -g | awk '/Mem/{print $2}') GB"
  echo "swap    $(free -g | awk '/Swap/{print $2}') GB"
  echo "swappy  $(cat /proc/sys/vm/swappiness)"
  echo "disk    $(df -h / | tail -1 | awk '{print $4}') bebas"
  echo "jobs    -j6"
  echo "----"
} > "$LOG"

source build/envsetup.sh >/dev/null 2>&1
lunch lineage_A37-bp1a-userdebug >/dev/null 2>&1

m -j6 bacon >> "$LOG" 2>&1
rc=$?

{
  echo "----"
  echo "SELESAI rc=$rc $(date '+%F %T')"
  echo "disk sisa $(df -h / | tail -1 | awk '{print $4}')"
  ls -l out/target/product/A37/*.zip 2>/dev/null
} >> "$LOG"
