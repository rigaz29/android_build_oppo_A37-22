#!/bin/bash
# Buktikan dari ZIP YANG DIKIRIM bahwa perubahan benar-benar sampai ke ROM.
#
# Kenapa harus dari zip: memeriksa berkas di out/ pernah menyesatkan dua kali --
# system/lib/libc.so ternyata symlink 44 byte, dan stempel waktunya lebih tua
# dari patch padahal patchnya masuk. Yang mengikat hanya artefak yang dikirim.
#
# system.img dikeluarkan SEKALI lalu dipakai untuk semua pemeriksaan, karena
# brotli + sdat2img memakan beberapa menit.

set -u
ZIP=${1:-$(ls -t /root/los22/out/target/product/A37/lineage-22.2-*.zip 2>/dev/null | head -1)}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
OBJDUMP=/root/los22/prebuilts/clang/host/linux-x86/llvm-binutils-stable/llvm-objdump

[ -f "$ZIP" ] || { echo "zip tidak ditemukan"; exit 1; }
echo "zip $(basename "$ZIP")  ($(stat -c%s "$ZIP") B)"
echo "sha $(sha256sum "$ZIP" | cut -c1-16)..."
echo

unzip -q -o "$ZIP" system.new.dat.br system.transfer.list -d "$W" || exit 1
brotli -d -o "$W/system.new.dat" "$W/system.new.dat.br" || exit 1
python3 /root/los22/tools/extract-utils/sdat2img.py \
  "$W/system.transfer.list" "$W/system.new.dat" "$W/system.img" >/dev/null || exit 1
# debugfs tidak bisa membaca Android sparse image, dan gejalanya menyesatkan:
# ls / balik kosong seolah isinya salah, padahal cuma formatnya.
if [ "$(head -c4 "$W/system.img" | xxd -p)" = "3aff26ed" ]; then
  /root/los22/out/host/linux-x86/bin/simg2img "$W/system.img" "$W/raw.img" || exit 1
  mv -f "$W/raw.img" "$W/system.img"
fi

gagal=0
periksa() {  # nama, perintah-yang-mengembalikan-0-kalau-lolos
  if eval "$2" >/dev/null 2>&1; then echo "  ✓ $1"; else echo "  ✗ $1"; gagal=1; fi
}

# ---- 1. bionic: rename() -> renameat (lihat verify-rename.sh untuk rinciannya)
debugfs -R "dump /system/apex/com.android.runtime.apex $W/rt.apex" "$W/system.img" 2>/dev/null
unzip -q -o -j "$W/rt.apex" apex_payload.img -d "$W" 2>/dev/null
debugfs -R "dump /lib/bionic/libc.so $W/libc.so" "$W/apex_payload.img" 2>/dev/null
echo "libc (APEX com.android.runtime):"
periksa "rename() -> renameat, bukan renameat2" \
  "$OBJDUMP -d --disassemble-symbols=rename '$W/libc.so' | grep -q 'Thunk_renameat\b\|<renameat>'"
periksa "stub renameat memakai syscall 329 (0x149)" \
  "$OBJDUMP -d --disassemble-symbols=renameat '$W/libc.so' | grep -q '#0x149'"

# ---- 2. libnetd_updatable: penjaga eBPF
# Penanda yang dicari adalah string log yang ditambahkan patch. Itu bukti
# langsung bahwa kode baru ikut terkompilasi, bukan sekadar berkas tergantikan.
debugfs -R "dump /system/apex/com.android.tethering.apex $W/teth.apex" "$W/system.img" 2>/dev/null
rm -f "$W/apex_payload.img"
unzip -q -o -j "$W/teth.apex" apex_payload.img -d "$W" 2>/dev/null
for p in /lib/libnetd_updatable.so /lib64/libnetd_updatable.so; do
  debugfs -R "dump $p $W/lnu.so" "$W/apex_payload.img" 2>/dev/null
  [ -s "$W/lnu.so" ] && break
done
echo "libnetd_updatable (APEX com.android.tethering):"
periksa "penjaga eBPF ikut terkompilasi" \
  "strings '$W/lnu.so' | grep -q 'eBPF tidak didukung perangkat ini'"

# ---- 3. bootwatchdog
rm -f "$W/bw.sh"
for p in /system/vendor/bin/bootwatchdog.sh /vendor/bin/bootwatchdog.sh \
         /system/bin/bootwatchdog.sh /system/vendor/etc/bootwatchdog.sh; do
  debugfs -R "dump $p $W/bw.sh" "$W/system.img" 2>/dev/null
  [ -s "$W/bw.sh" ] && { echo "bootwatchdog ($p):"; break; }
done
if [ -s "$W/bw.sh" ]; then
  periksa "batas default 300 detik" "grep -q 'BATAS=300' '$W/bw.sh'"
  periksa "pagu mutlak masih 600 detik" "grep -q 'BATAS_MAKS=600' '$W/bw.sh'"
else
  echo "  ✗ bootwatchdog.sh tidak ketemu di system.img"; gagal=1
fi

echo
[ $gagal -eq 0 ] && echo "SEMUA GERBANG LOLOS" || echo "ADA GERBANG YANG GAGAL"
exit $gagal
