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
    local repo="$1" p="$2" name subj
    name="$(basename "$p")"
    if [ ! -f "$p" ]; then
        printf '  ?? %-58s BERKAS PATCH TIDAK ADA\n' "${name:0:58}"; fail=$((fail+1)); return
    fi
    # Deteksi "sudah diterapkan" lewat judul commit, BUKAN lewat
    # `git apply --check -R`. Uji terap-terbalik tidak andal untuk patch yang
    # isinya revert-of-revert (0008): konteksnya tidak cocok saat dibalik,
    # sehingga patch yang SUDAH terpasang dilaporkan gagal.
    # git melipat Subject panjang ke baris lanjutan yang diawali spasi
    # (0008 salah satunya), jadi lipatannya harus dibuka dulu sebelum
    # dibandingkan dengan judul commit.
    subj="$(awk '
        /^Subject: / {
            sub(/^Subject: (\[[^]]*\] )?/, "")
            s = $0
            while ((getline line) > 0) {
                if (line ~ /^[ \t]/) { sub(/^[ \t]+/, "", line); s = s " " line }
                else break
            }
            print s; exit
        }' "$p")"
    if [ -n "$subj" ] && git -C "$repo" log --format='%s' -100 2>/dev/null | grep -qxF "$subj"; then
        printf '  == %-58s sudah ada\n' "${name:0:58}"; skip=$((skip+1)); return
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

echo "== frameworks/base: lima patch UL di atas basis RESMI =="
# frameworks/base memakai LineageOS RESMI, bukan fork ULH. Alasan lengkapnya
# ada di komentar A37-22.xml; ringkasnya: empat kegagalan build berturut-turut
# yang semuanya berakar pada fork ULH yang tertinggal 295 commit.
#
# Kelima patch di bawah adalah SATU-SATUNYA hal yang fork ULH sumbangkan dan
# masih relevan untuk A37. Diambil apa adanya dari kit LOS 21, tempat kelimanya
# sudah diterapkan di atas frameworks/base resmi dan terbukti build serta boot.
#
#   0004/0005  matikan efek stretch dan ripple PATTERNED  (GPU lemah)
#   0006       properti night mode saat battery saver
#   0008/0009  toleransi galat cgroup                     (kernel 3.10)
for p in 0004-Don-t-use-stretch-effect-by-default \
         0005-Don-t-use-PATTERNED-style-ripple-effect-by-default \
         0006-batterysaver-add-property-to-disable-night-mode-on-b \
         0008-Revert-Revert-Treat-process-group-creation-failure-d \
         0009-Ignore-cgroup-creation-errors; do
    terap frameworks/base "$KIT/patches/frameworks_base_ul21/$p.patch"
done

# CATATAN: patches/frameworks_base/0201-0204 SENGAJA TIDAK dipakai lagi.
# Keempatnya menambal fork ULH (nama modul powershare, resource yang hilang,
# dan pencabutan dua revert telephony). Di atas basis resmi keempatnya
# tidak diperlukan. Disimpan sebagai arsip diagnosis, bukan untuk diterapkan.


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
