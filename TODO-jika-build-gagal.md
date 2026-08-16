# Tindakan tertunda: hanya dijalankan kalau build gagal

Diputuskan 16 Agustus 2026, saat build percobaan 4 berjalan di 30% tanpa kegagalan.

**Pemicu:** `^FAILED:` muncul di `build-fase4.log`.
**Bukan pemicu:** build selesai `rc=0`. Kalau ROM jadi, biarkan apa adanya —
menambahkan ini setelahnya berarti rebuild penuh 5–7 jam, dan itu keputusan
terpisah.

## Yang dikerjakan sebelum rebuild

### 1. Nyalakan `WITH_ADB_INSECURE`

Di `device/oppo/A37/lineage_A37.mk`, baris terakhir blok panjangnya:

```diff
-# WITH_ADB_INSECURE := true
+WITH_ADB_INSECURE := true
```

⚠️ **Uncomment, jangan setel `false` untuk mematikan.**
`vendor/lineage/config/common.mk` memakai `ifdef WITH_ADB_INSECURE`, dan `ifdef`
di GNU Make bernilai benar untuk nilai apa pun yang tidak kosong — termasuk
string `"false"`. Terbukti di build `20260808_130028`: `ro.adb.secure` masih 0
meski flag sudah disetel `false`. Untuk mematikan lagi, **komentari**.

### 2. Pasang kunci adb mesin build

Blok `PRODUCT_ADB_KEYS` sudah ada di `lineage_A37.mk` tapi tidak aktif, dijaga
`ifneq ($(wildcard device/oppo/A37/adb_keys),)`. Berkasnya tinggal disalin:

```bash
cp /root/.android/adbkey.pub /root/los22/device/oppo/A37/adb_keys
```

⚠️ `PRODUCT_ADB_KEYS` **sendirian tidak cukup** sejak Android 14: ia memasang ke
`TARGET_ROOT_OUT`, sedangkan A14+ tidak lagi memakai `root/` sebagai sumber
ramdisk. Yang benar-benar bekerja adalah `PRODUCT_COPY_FILES` ke
`TARGET_COPY_OUT_RAMDISK` — dan blok itu sudah menyertakan keduanya.

### 3. Verifikasi sampai ke artefak yang dikirim, bukan yang dibuat

Percobaan pertama LOS 21 sempat salah menyatakan fitur ini bekerja karena hanya
memeriksa berkas yang **dibuat**, bukan yang **ada di dalam** `boot.img`:

```bash
unzip -p <rom>.zip boot.img > /tmp/b.img
tools/qbootimg.py /tmp/b.img   # lalu cari /adb_keys di dalam ramdisk
```

Dan setelah flash:

```bash
adb shell getprop ro.adb.secure        # harus 0
adb shell getprop persist.sys.usb.config
```

## Keamanan

ROM dengan `WITH_ADB_INSECURE := true` **tidak boleh dibagikan** — siapa pun yang
mencolokkan USB mendapat shell tanpa dialog otorisasi RSA. Untuk perangkat uji
sendiri diterima; matikan (komentari) sebelum ada build yang beredar.

`adb_keys` juga di-gitignore: ia kunci publik, tapi mengirimkannya di ROM berarti
setiap ROM dari tree ini memercayai mesin build ini.

Catatan: keduanya tidak menolong kalau kegagalan terjadi **sebelum adbd hidup**.
Untuk kelas itu andalkan ramoops — dan sejak LOS 21, TWRP di perangkat ini sudah
bisa membaca `/sys/fs/pstore`.
