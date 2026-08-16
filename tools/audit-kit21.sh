#!/bin/bash
# Audit seluruh patch kit LOS 21 terhadap pohon LOS 22 -- BACA SAJA, tidak mengubah apa pun.
#
# Alasan alat ini ada: tiga patch yang sudah tersedia di kit LOS 21 lolos dari
# perhatian dan baru ketahuan setelah gerbang menabraknya --
#   String8::string()   -> satu siklus build (~1 jam)
#   zip -y              -> satu siklus build (~1 jam)
#   bionic renameat2    -> satu siklus build PLUS satu siklus flash fisik
# Ketiganya terap bersih begitu dicoba. Kalau audit ini dijalankan di muka,
# ketiganya muncul dalam hitungan detik.
#
# Klasifikasi per patch:
#   SUDAH   revert-nya terap bersih -> perbaikan sudah ada di pohon
#   ABSEN   patch maju terap bersih -> hunknya TIDAK ada di pohon  <- periksa ini
#   BEDA    dua-duanya gagal -> konteks bergeser, butuh penilaian manusia
#   -       repo tujuan tidak ada di pohon ini
#
# ABSEN bukan berarti wajib diterapkan. Banyak patch UL 21 tidak berlaku di 22
# (mis. fork ULH sudah membawa perbaikannya lewat jalur lain, atau hulu sudah
# mencabut kodenya). Gunanya mempersempit 138 jadi daftar pendek untuk ditimbang.

KIT21=${KIT21:-/root/a37-22/base/android_build_oppo_A37-21/patches}
TREE=${TREE:-/root/los22}
[ -d "$KIT21" ] || KIT21=/root/a37-21/patches

repo_of() {
  case "${1#ul21/}" in
    bionic) echo bionic ;;
    build_make) echo build/make ;;
    build_soong) echo build/soong ;;
    art) echo art ;;
    external_perfetto) echo external/perfetto ;;
    device_lineage_sepolicy) echo device/lineage/sepolicy ;;
    frameworks_av) echo frameworks/av ;;
    frameworks_base) echo frameworks/base ;;
    frameworks_native) echo frameworks/native ;;
    hardware_interfaces) echo hardware/interfaces ;;
    kernel) echo kernel/oppo/msm8939 ;;
    system_bpf) echo system/bpf ;;
    system_core) echo system/core ;;
    system_libhidl) echo system/libhidl ;;
    system_netd) echo system/netd ;;
    system_sepolicy) echo system/sepolicy ;;
    vendor_lineage) echo vendor/lineage ;;
    qcom-caf_msm8916_audio) echo hardware/qcom-caf/msm8916/audio ;;
    qcom-caf_msm8916_display) echo hardware/qcom-caf/msm8916/display ;;
    packages_modules_adb) echo packages/modules/adb ;;
    packages_modules_Bluetooth) echo packages/modules/Bluetooth ;;
    packages_modules_Connectivity) echo packages/modules/Connectivity ;;
    packages_modules_IntentResolver) echo packages/modules/IntentResolver ;;
    packages_modules_NetworkStack) echo packages/modules/NetworkStack ;;
    *) echo "" ;;
  esac
}

# Berkas yang PINDAH antara 21 dan 22 membuat patch gagal terap maju MAUPUN
# mundur, jadi ia jatuh ke BEDA -- kategori paling besar dan paling mudah
# dikesampingkan. Itu persis yang terjadi pada perbaikan netd BPF-less:
# netd/NetdUpdatable.cpp (21) -> bpf/netd/NetdUpdatable.cpp (22). Ongkosnya
# satu siklus flash fisik. Fungsi ini memisahkan "pindah" dari "berubah".
cek_pindah() {
  local patch=$1 repo=$2 hasil=""
  local f base found
  for f in $(grep -oE '^\+\+\+ b/\S+' "$patch" | sed 's|^+++ b/||' | sort -u); do
    [ -e "$TREE/$repo/$f" ] && continue          # masih di tempatnya
    base=$(basename "$f")
    found=$(find "$TREE/$repo" -name "$base" -not -path '*/.git/*' 2>/dev/null | head -1)
    [ -n "$found" ] && hasil="$hasil ${f} -> ${found#$TREE/$repo/}"
  done
  echo "$hasil"
}

absen=0; sudah=0; beda=0; nihil=0; pindah=0
declare -a LIST_ABSEN LIST_PINDAH

while IFS= read -r p; do
  rel=${p#$KIT21/}
  dir=$(dirname "$rel")
  repo=$(repo_of "$dir")
  if [ -z "$repo" ] || [ ! -d "$TREE/$repo/.git" ]; then
    printf '  %-7s %s\n' "-" "$rel"; nihil=$((nihil+1)); continue
  fi
  if git -C "$TREE/$repo" apply --check -R "$p" 2>/dev/null; then
    printf '  %-7s %s\n' "SUDAH" "$rel"; sudah=$((sudah+1))
  elif git -C "$TREE/$repo" apply --check "$p" 2>/dev/null; then
    printf '  %-7s %s\n' "ABSEN" "$rel"; absen=$((absen+1)); LIST_ABSEN+=("$repo|$rel")
  else
    mv=$(cek_pindah "$p" "$repo")
    if [ -n "$mv" ]; then
      printf '  %-7s %s\n' "PINDAH" "$rel"; pindah=$((pindah+1))
      LIST_PINDAH+=("$repo|$rel|$mv")
    else
      printf '  %-7s %s\n' "BEDA" "$rel"; beda=$((beda+1))
    fi
  fi
done < <(find "$KIT21" -name '*.patch' | sort)

echo
echo "=============================================="
echo "SUDAH ada di pohon      : $sudah"
echo "ABSEN (hunk tidak ada)  : $absen   <- timbang satu per satu"
echo "PINDAH (berkas berpindah): $pindah  <- PALING MUDAH TERLEWAT"
echo "BEDA (konteks bergeser) : $beda"
echo "repo tidak ada          : $nihil"
echo "=============================================="

if [ ${#LIST_PINDAH[@]} -gt 0 ]; then
  echo
  echo "PINDAH -- patch gagal terap hanya karena berkasnya berpindah tempat."
  echo "Isinya bisa jadi masih relevan sepenuhnya; port dengan tangan."
  printf '%s\n' "${LIST_PINDAH[@]}" | sort | awk -F'|' '
    $1!=prev { printf "\n  [%s]\n", $1; prev=$1 }
    { printf "    %s\n", $2; n=split($3,a," "); for(i=1;i<=n;i+=3) printf "      %s %s %s\n", a[i], a[i+1], a[i+2] }'
fi

if [ ${#LIST_ABSEN[@]} -gt 0 ]; then
  echo
  echo "Daftar ABSEN, dikelompokkan per repo:"
  printf '%s\n' "${LIST_ABSEN[@]}" | sort | awk -F'|' '
    $1!=prev { printf "\n  [%s]\n", $1; prev=$1 } { printf "    %s\n", $2 }'
fi
