#!/bin/bash
# Gerbang konfigurasi Fase 3: jalankan terlepas dari sesi, karena analisis
# Soong penuh butuh ~20 menit sedangkan background task sesi diputus ~11 menit.
cd /root/los22 || exit 1
export LC_ALL=C
LOG=/root/los22/soong-fase3g.log
echo "mulai $(date '+%F %T')" > "$LOG"
source build/envsetup.sh >/dev/null 2>&1
lunch lineage_A37-bp1a-userdebug >/dev/null 2>&1
m nothing >> "$LOG" 2>&1
echo "SELESAI rc=$? $(date '+%F %T')" >> "$LOG"
