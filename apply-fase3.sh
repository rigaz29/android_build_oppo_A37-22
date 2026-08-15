#!/bin/bash
# Fase 3 - perbaikan agar pohon LOS 22.2 lolos gerbang konfigurasi untuk A37.
#
# Jalankan dari akar pohon LOS 22.2 (yang berisi .repo/):
#
#   ./apply-fase3.sh
#
# Kedua patch di sini menambal FORK ULTRA-LEGACY-HIPPEASTRUM, bukan device tree.
# Sebabnya sama untuk keduanya: fork ULH lineage-22.2 (dorongan terakhir Mei
# 2026) tertinggal dari basis LineageOS resmi yang disinkronkan bersamanya.
# Ini kelas risiko yang sudah dicatat di PLAN-LOS22.md 7, dan sekarang terbukti.
#
# Perbaikan device tree TIDAK ada di sini -- sudah menyatu di
# rb_device_oppo_A37 branch lineage-22 (commit cae3f05).

set -u

ROOT="$(pwd)"
KIT="$(cd "$(dirname "$0")" && pwd)"

[ -d "$ROOT/.repo" ] || { echo "FATAL: jalankan dari akar pohon LOS (tidak ada .repo/)"; exit 1; }

ok=0; skip=0; fail=0

terap() {
    local repo="$1" p="$2" name
    name="$(basename "$p")"
    if [ ! -f "$p" ]; then
        printf '  ?? %-58s BERKAS PATCH TIDAK ADA\n' "${name:0:58}"; fail=$((fail+1)); return
    fi
    if git -C "$repo" apply --check -R "$p" 2>/dev/null; then
        printf '  == %-58s sudah ada\n' "${name:0:58}"; skip=$((skip+1)); return
    fi
    if git -C "$repo" am --quiet "$p" 2>/dev/null; then
        printf '  ok %-58s\n' "${name:0:58}"; ok=$((ok+1))
    else
        git -C "$repo" am --abort 2>/dev/null
        printf '  XX %-58s GAGAL\n' "${name:0:58}"; fail=$((fail+1))
    fi
}

echo "== frameworks/native: mekanisme gralloc usage bits =="
# Fork ULH memakai defaults: ["gralloc_10_usage_bits_defaults"], modul yang
# TIDAK ADA di pohon 22.2. Basis resmi memakai select() atas soong config
# variable, dan variabel itulah yang disuapi vendor/lineage dari
# TARGET_ADDITIONAL_GRALLOC_10_USAGE_BITS di BoardConfig A37 (baris 402).
# Karena itu rujukannya tidak boleh sekadar dihapus.
terap frameworks/native "$KIT/patches/frameworks_native/0201-libui-pakai-mekanisme-gralloc-usage-bits-yang-dipaka.patch"

echo "== frameworks/base: nama modul AIDL powershare =="
# Fork ULH: vendor.lineage.powershare-V1.0-java (gaya lama).
# hardware/lineage/interfaces resmi menghasilkan -V1-java.
terap frameworks/base "$KIT/patches/frameworks_base/0201-SystemUI-perbaiki-nama-modul-AIDL-powershare-untuk-b.patch"

echo
echo "ringkasan: $ok diterapkan, $skip sudah ada, $fail gagal"

echo
echo "== gerbang Fase 3 =="
echo "  lunch lineage_A37-bp1a-userdebug   <- format TIGA bagian, release bp1a"
echo "  m nothing                          <- harus rc=0 (perlu sekitar 20 menit)"
echo
echo "  Prasyarat yang mudah terlewat: entri hardware/qcom-caf/common di local"
echo "  manifest HARUS membawa 22 <linkfile> os_pickup. Tanpa itu 443 galat"
echo "  'module already defined'. Lihat komentar di A37-22.xml."

[ "$fail" -eq 0 ] || exit 1
