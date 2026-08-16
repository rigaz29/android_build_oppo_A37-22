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


echo "== device/qcom/sepolicy-legacy: atribut HAL yang dirujuk lineage sepolicy =="
# sepolicy.mk:27 pohon legacy menarik masuk device/lineage/sepolicy/qcom (milik
# LineageOS resmi), yang mengasumsikan device/qcom/sepolicy MODERN. Tanpa patch
# ini kompilasi sepolicy gagal di 38%:
#   platform_app.te:1: ERROR 'attribute vendor_hal_soter_client is not declared'
terap device/qcom/sepolicy-legacy \
      "$KIT/patches/device_qcom_sepolicy_legacy/0301-public-attributes-deklarasikan-vendor_hal_soter-saja.patch"

echo "== device/lineage/sepolicy: pulihkan dukungan ultra-legacy =="
# LineageOS resmi mencabut dukungan platform ultra-legacy dari repo ini, dan ULH
# tidak menyediakan fork untuk 22.2 (hanya 23.2). Tanpa patch ini build gagal:
#   common/hal_gnss_qti.te:31: ERROR 'unknown type vendor_hal_gnss_qti_exec'
# karena substitusi M4 mengganti `hal_gnss_qti` tapi tidak `hal_gnss_qti_exec`.
# Patch ini mengeluarkan msm8916 dari substitusi itu sama sekali.
terap device/lineage/sepolicy \
      "$KIT/patches/device_lineage_sepolicy/0401-Pulihkan-dukungan-sepolicy-ultra-legacy-untuk-msm891.patch"

echo "== hardware/qcom-caf/wlan: jalur WCNSS QMI OSS =="
# Android.mk menyetel -DWCNSS_QMI tanpa syarat lalu menambah -DWCNSS_QMI_OSS,
# sehingga wcnss_init_qmi dideklarasikan dua kali dengan jenis berbeda
# (fungsi di header, pointer di wcnss_service.c). A37 memakai jalur OSS ini
# secara sengaja; libwcnss_qmi.so-nya dibangun device tree dari wcnss_oppo/.
terap hardware/qcom-caf/wlan \
      "$KIT/patches/hardware_qcom-caf_wlan/0501-wcnss-service-jangan-tarik-wcnss_qmi_client.h-di-jal.patch"

echo "== system/sepolicy: cabut sysfs_disk_stat yang melanggar uji beku =="
# Fork ULH mengembalikan tipe sysfs_disk_stat (dicabut AOSP di A15) tapi tidak
# menambahkannya ke prebuilts/api/202404, sehingga se_freeze_test menolak build:
#   The following public types were added: sysfs_disk_stat
terap system/sepolicy "$KIT/patches/system_sepolicy/0601-Revert-Fix-storaged-access-to-sys-block-mmcblk0-stat.patch"

echo "== device/qcom/sepolicy-legacy: selaraskan dengan sepolicy_test A15 =="
# 58 pelanggaran di lima kelas dengan aturan BERLAWANAN. Lihat badan commit
# patch 0302 untuk keputusan per kelas.
terap device/qcom/sepolicy-legacy \
      "$KIT/patches/device_qcom_sepolicy_legacy/0302-Selaraskan-sepolicy-legacy-dengan-sepolicy_test-Andr.patch"

echo "== build/make: zip -y saat mengemas OTA =="
# non_ab_ota.py memanggil zip TANPA -y, sehingga zip MENGIKUTI symlink alih-alih
# menyimpannya. target_files memuat RECOVERY/RAMDISK/d -> /sys/kernel/debug, jadi
# zip menelusuri debugfs MESIN BUILD dan gagal di langkah pengemasan terakhir:
#   zip I/O error: Bad address
# Terpicu hanya bila target_file berupa DIREKTORI (jalur LineageOS) DAN build
# berjalan sebagai root -- keduanya berlaku di sini.
terap build/make "$KIT/patches/build_make/0701-releasetools-zip-y-agar-symlink-tidak-diikuti.patch"

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
