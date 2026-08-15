#!/bin/bash
# Fase 1 - patch userspace BPF-less untuk OPPO A37 di LineageOS 22.2
#
# Jalankan dari akar pohon LOS 22.2 (yang berisi .repo/).
#
#   GSI=/path/ke/MisterZtr/LineageOS_gsi ./apply-fase1.sh
#
# GSI menunjuk ke klon MisterZtr/LineageOS_gsi branch lineage-22.2:
#   git clone -b lineage-22.2 --depth 1 https://github.com/MisterZtr/LineageOS_gsi
#
# Kernel A37 tidak punya CONFIG_BPF_SYSCALL sama sekali, jadi bpffs tidak
# terdaftar dan setiap operasi /sys/fs/bpf gagal. Tanpa patch di bawah, netd
# menggantung selamanya menunggu bpf.progs_loaded dan system_server macet di
# StartNetworkManagementService - kegagalan boot LOS 21 yang sudah terdiagnosis.
#
# Set MisterZtr menutup sebagian besar jalur, TAPI TIDAK CUKUP sendirian:
# empat titik fatal tersisa dan ditambal oleh patches/ di repo ini.

set -u

ROOT="$(pwd)"
KIT="$(cd "$(dirname "$0")" && pwd)"
GSI="${GSI:-}"

[ -d "$ROOT/.repo" ] || { echo "FATAL: jalankan dari akar pohon LOS (tidak ada .repo/)"; exit 1; }
[ -n "$GSI" ] && [ -d "$GSI/patches/trebledroid" ] || {
    echo "FATAL: setel GSI ke klon MisterZtr/LineageOS_gsi branch lineage-22.2"; exit 1; }

ok=0; skip=0; fail=0

# terap() <path-project> <berkas-patch>
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

T="$GSI/patches/trebledroid"

echo "== packages/modules/Connectivity (trebledroid) =="
for f in 0001-Allow-failing-to-load-bpf-programs-for-BPF-less-devi \
         0002-Support-non-working-BPF-maps-on-old-BPF-less-kernel \
         0003-Bring-back-traffic-indicators-for-legacy-devices \
         0006-More-bpf-errors-ignore-there-are-some-4.14-without-t \
         0007-Revert-netdupdatable-add-back-abort-on-init-fail \
         0008-Additional-bpf-prevent-crash; do
    terap packages/modules/Connectivity "$T/platform_packages_modules_Connectivity/$f.patch"
done
# 0004 (V gsi on pixel 5 R base kernel) SENGAJA DILEWATI - khusus citra GSI.

echo "== system/bpf (trebledroid) =="
terap system/bpf "$T/platform_system_bpf/0001-Support-no-bpf-usecase.patch"

echo "== system/netd (trebledroid) =="
terap system/netd "$T/platform_system_netd/0003-Support-no-bpf-usecase.patch"
terap system/netd "$T/platform_system_netd/0004-Don-t-abort-in-case-of-cgroup-bpf-setup-fail-since-s.patch"

echo "== packages/modules/DnsResolver (trebledroid) =="
terap packages/modules/DnsResolver \
      "$T/platform_packages_modules_DnsResolver/0001-Dont-abort-if-the-DnsHelper-failed-to-init-on-BPF-le.patch"

echo "== frameworks/native (trebledroid) =="
terap frameworks/native "$T/platform_frameworks_native/0012-Disable-gpuservice-on-old-BPF-less-kernel.patch"

echo "== patch A37 sendiri - WAJIB, set MisterZtr tidak menutup ini =="
terap packages/modules/Connectivity \
      "$KIT/patches/packages_modules_Connectivity/0101-netbpfload-createSysFsBpfSubDir-jangan-mematikan-doL.patch"
terap system/bpf \
      "$KIT/patches/system_bpf/0101-bpfloader-createBpfFsSubDirectories-jangan-exit-di-k.patch"

echo
echo "ringkasan: $ok diterapkan, $skip sudah ada, $fail gagal"

echo
echo "== gerbang: rantai bpf.progs_loaded harus bebas jalur keluar dini =="
# Catatan: pola harus mengabaikan komentar. Patch kita menyebut "exit(120)" di
# dalam komentar penjelas, jadi pencarian polos akan cocok dengan teks itu dan
# melaporkan gerbang gagal padahal kodenya sudah benar. Karena itu kedua pola
# diikat ke awal baris (kode ter-indentasi), bukan ke mana pun di dalam baris.
sisa=$(grep -cE '^[[:space:]]*if \(createSysFsBpfSubDir\(.*\)\) return 1;' \
       packages/modules/Connectivity/bpf/loader/NetBpfLoad.cpp 2>/dev/null) || sisa=0
exit120=$(grep -cE '^[[:space:]]*exit\(120\);' \
       system/bpf/loader/Loader.cpp 2>/dev/null) || exit120=0
echo "  NetBpfLoad createSysFsBpfSubDir yang masih fatal : $sisa  (harus 0)"
echo "  Loader.cpp exit(120)                             : $exit120  (harus 0)"

[ "$fail" -eq 0 ] && [ "$sisa" -eq 0 ] && [ "$exit120" -eq 0 ] || exit 1
