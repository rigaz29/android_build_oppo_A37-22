#!/bin/bash
# Buktikan dari ZIP YANG DIKIRIM bahwa rename() tidak lagi memakai renameat2.
#
# Kenapa harus dari zip dan bukan dari out/: proyek 21 pernah salah menyimpulkan
# sebuah fitur bekerja karena hanya memeriksa berkas yang DIBUAT, bukan yang
# DIKIRIM. Jalur di sini lengkap: zip -> brotli -> sdat2img -> debugfs -> objdump.
#
# Lolos kalau:
#   1. rename() melompat ke renameat (bukan renameat2)
#   2. renameat ada sebagai stub syscall sungguhan dengan nomor 329
#      -- ini hanya terbentuk kalau SYSCALLS.TXT mencantumkannya

set -u
ZIP=${1:-$(ls -t /root/los22/out/target/product/A37/lineage-22.2-*.zip 2>/dev/null | head -1)}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
OBJDUMP=/root/los22/prebuilts/clang/host/linux-x86/llvm-binutils-stable/llvm-objdump

[ -f "$ZIP" ] || { echo "zip tidak ditemukan"; exit 1; }
echo "zip   $(basename "$ZIP")  ($(stat -c%s "$ZIP") B)"
echo "sha   $(sha256sum "$ZIP" | cut -c1-16)..."
echo

echo "[1/4] keluarkan system.new.dat.br + transfer list dari zip"
unzip -q -o "$ZIP" system.new.dat.br system.transfer.list -d "$W" || exit 1

echo "[2/4] brotli -d"
brotli -d -o "$W/system.new.dat" "$W/system.new.dat.br" || exit 1

echo "[3/4] sdat2img -> system.img"
python3 /root/los22/tools/extract-utils/sdat2img.py \
  "$W/system.transfer.list" "$W/system.new.dat" "$W/system.img" >/dev/null || exit 1

echo "[4/4] debugfs: keluarkan libc.so"
# sdat2img bisa mengembalikan Android sparse image (magic 3aff26ed), dan debugfs
# TIDAK bisa membacanya -- gejalanya menyesatkan: "ls /" balik kosong dan setiap
# path tampak tidak ada, seolah isinya yang salah padahal formatnya.
if [ "$(head -c4 "$W/system.img" | xxd -p)" = "3aff26ed" ]; then
  echo "  sparse image -> simg2img"
  /root/los22/out/host/linux-x86/bin/simg2img "$W/system.img" "$W/raw.img" || exit 1
  mv -f "$W/raw.img" "$W/system.img"
fi

# PENTING: di Android modern libc yang DIPAKAI dikirim di dalam APEX
# com.android.runtime, bukan di /system/lib. Berkas out/target/product/A37/
# system/lib/libc.so memang ada tapi merupakan sisa lama -- stempel waktunya
# bahkan lebih tua dari patch dan disassembly-nya kosong. Memverifikasi berkas
# itu akan memberi kesimpulan yang salah dengan meyakinkan.
LIBC=""
for apex in /apex/com.android.runtime.apex /apex/com.android.runtime_stripped.apex; do
  rm -f "$W/rt.apex"
  debugfs -R "dump $apex $W/rt.apex" "$W/system.img" 2>/dev/null
  [ -s "$W/rt.apex" ] || continue
  for inner in lib/bionic/libc.so lib64/bionic/libc.so; do
    if unzip -q -o -j "$W/rt.apex" "$inner" -d "$W" 2>/dev/null && [ -s "$W/libc.so" ]; then
      LIBC="$apex!$inner"; break 2
    fi
  done
done
# fallback: tata letak lama (libc langsung di partisi)
if [ -z "$LIBC" ]; then
  for cand in /lib/libc.so /lib64/libc.so; do
    rm -f "$W/libc.so"
    debugfs -R "dump $cand $W/libc.so" "$W/system.img" 2>/dev/null
    [ -s "$W/libc.so" ] && { LIBC=$cand; break; }
  done
fi
if [ -z "$LIBC" ]; then
  echo "  libc.so tidak ketemu. Isi /apex:"
  debugfs -R "ls /apex" "$W/system.img" 2>&1 | head -5 | sed 's/^/    /'
  exit 1
fi
echo "  $LIBC  ($(stat -c%s "$W/libc.so") B)"
echo

echo "=============== rename() ==============="
DIS=$("$OBJDUMP" -d --disassemble-symbols=rename "$W/libc.so" 2>/dev/null)
echo "$DIS" | grep -E '^\s+[0-9a-f]+:' | tail -6
echo
if echo "$DIS" | grep -q 'renameat2'; then
  echo "  ✗ GAGAL: rename() masih memanggil renameat2"; exit 1
elif echo "$DIS" | grep -q 'renameat'; then
  echo "  ✓ rename() -> renameat"
else
  echo "  ? target lompatan tidak terbaca -- periksa manual"; exit 1
fi

echo
echo "=========== stub syscall renameat ==========="
"$OBJDUMP" -d --disassemble-symbols=renameat "$W/libc.so" 2>/dev/null \
  | grep -E '^\s+[0-9a-f]+:' | head -6
if "$OBJDUMP" -d --disassemble-symbols=renameat "$W/libc.so" 2>/dev/null \
   | grep -qE '#329|0x149'; then
  echo "  ✓ nomor syscall 329 hadir -- SYSCALLS.TXT memang mengekspor renameat"
else
  echo "  ! nomor 329 tidak terlihat langsung (bisa dimuat via register) -- periksa manual"
fi
