# Tindakan tertunda: hanya dijalankan kalau build gagal

Diputuskan 16 Agustus 2026, saat build percobaan 4 berjalan tanpa kegagalan.

**Pemicu:** `^FAILED:` muncul di `build-fase4.log`.
**Bukan pemicu:** build selesai `rc=0`. Kalau ROM jadi, biarkan apa adanya —
menambahkan ini setelahnya berarti rebuild penuh 5–7 jam, dan itu keputusan
terpisah.

## Yang dikerjakan sebelum rebuild

### Nyalakan `WITH_ADB_INSECURE`

Di `device/oppo/A37/lineage_A37.mk`, baris terakhir blok panjangnya:

```diff
-# WITH_ADB_INSECURE := true
+WITH_ADB_INSECURE := true
```

Efeknya (`vendor/lineage/config/common.mk:31-33`): `ro.adb.secure=0`, yaitu
otentikasi adb **dimatikan sepenuhnya**. Rantai lanjutannya di
`post_process_props.py` menambahkan `adb` ke `persist.sys.usb.config`, sehingga
adb hidup sejak boot pertama tanpa dialog otorisasi RSA.

⚠️ **Untuk mematikannya nanti: KOMENTARI, jangan setel `false`.**
`common.mk` memakai `ifdef WITH_ADB_INSECURE`, dan `ifdef` di GNU Make bernilai
benar untuk nilai apa pun yang tidak kosong — termasuk string `"false"`.
Terbukti di build `20260808_130028`: `ro.adb.secure` masih 0 meski flag sudah
disetel `false`.

### `adb_keys` — SENGAJA TIDAK DIPAKAI

Diputuskan 16 Agustus 2026: akses adb shell memang dikehendaki terbuka untuk
siapa pun, bukan dibatasi ke mesin build. Karena itu blok `PRODUCT_ADB_KEYS` di
`lineage_A37.mk` dibiarkan tidak aktif — penjaganya
`ifneq ($(wildcard device/oppo/A37/adb_keys),)` dan berkasnya memang tidak ada.

Jangan menyalin `adbkey.pub` ke sana. `WITH_ADB_INSECURE` sudah membuat dialog
otorisasi tidak muncul sama sekali, jadi `adb_keys` tidak menambah apa pun
selain mempersempit akses — kebalikan dari yang diinginkan.

## Verifikasi setelah flash

```bash
adb shell getprop ro.adb.secure          # harus 0
adb shell getprop persist.sys.usb.config # harus memuat "adb"
```

Verifikasi harus sampai ke artefak yang **dikirim**, bukan yang dibuat di `out/`.
Percobaan pertama LOS 21 sempat salah menyimpulkan fitur adb bekerja karena
hanya memeriksa berkas yang dibuat, bukan yang ada di dalam `boot.img`.

## Konsekuensi yang disengaja

ROM ini memberi **shell adb tanpa otorisasi kepada siapa pun yang mencolokkan
USB**. Itu pilihan sadar untuk perangkat uji. Kalau suatu saat ROM dari tree ini
dibagikan, komentari flag-nya lebih dulu.

Catatan: flag ini tidak menolong kalau kegagalan terjadi **sebelum `adbd` hidup**.
Untuk kelas itu andalkan ramoops — TWRP di perangkat ini sudah bisa membaca
`/sys/fs/pstore`.
