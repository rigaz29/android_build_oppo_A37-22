# Dua crash yang tidak terlihat di logcat

Keduanya ditemukan setelah ROM dinyatakan sehat: nol peringatan dalam sapuan
log, semua servis berjalan, tidak ada ANR. Keduanya tetap crash setiap boot.
Yang membuatnya luput bukan kelangkaan, melainkan **tempat kejadiannya**.

## Jebakan: `logcat -c` menghapus buffer crash

Pemeriksaan pertama terhadap `logcat -b crash` menghasilkan 20 baris. Sebelum
sempat dibaca, perintah `adb logcat -c` berikutnya menghapusnya — perintah itu
tanpa `-b` membersihkan buffer default **main, system, dan crash sekaligus**.
Bukti yang mau diperiksa hilang oleh alat pemeriksanya sendiri.

Tiga sumber bertahan terhadap `logcat -c`, dan ketiganya dipakai untuk memulihkan:

| Sumber | Isi |
|---|---|
| `/data/tombstones/` | crash native (SIGSEGV, SIGABRT) |
| `logcat -b events` | `am_crash`, `am_anr`, `am_proc_died` |
| `/data/system/dropbox/` | laporan crash yang disimpan framework |

Aturan praktisnya: **jangan pernah `logcat -c` sebelum membaca buffer crash**,
dan kalau terlanjur, `-b events` biasanya masih menyimpan jejaknya.

---

# 1. HWComposer SIGABRT — balapan izin, bukan bug grafis

Tidak ada gejala yang terlihat. Layar normal, tidak ada kedip, tidak ada log
error. Ditemukan hanya karena `/data/tombstones/` diperiksa:

```
LineageOS Version: '22.2-20260818_232933-UNOFFICIAL-A37'
Cmdline: /vendor/bin/hw/android.hardware.graphics.composer@2.1-service
signal 6 (SIGABRT)
Abort message: 'RefBase: object 0xf437512c with strong count 1 deleted. Double owned?'

#03 libutils.so               android::RefBase::~RefBase()+150
#04 libqdutils.so             IdleInvalidator::~IdleInvalidator()+20
#05 hwcomposer.msm8916.so     qhwc::MDPComp::init(hwc_context_t*)+246
#06 hwcomposer.msm8916.so     qhwc::initContext(hwc_context_t*)+576
#07 hwcomposer.msm8916.so     hwc_device_open(...)+42
```

## Sebabnya ada di dalam tombstone itu sendiri

Tombstone menyimpan potongan log terakhir sebelum abort. Dua baris terakhirnya
memberi urutan sebab tanpa celah tafsir:

```
E qdutils : setIdleTimeout:Unable to open
            /sys/devices/virtual/graphics/fb0/idle_time node Permission denied
F RefBase : RefBase: object 0x... with strong count 1 deleted. Double owned?
```

Blob gagal membuka node, lalu menghapus objek `IdleInvalidator` dengan `delete`
mentah — padahal objek itu turunan `android::Thread` dan thread-nya masih
memegang satu strong reference. Di Android 5.1 pola itu lolos diam-diam;
`RefBase` modern menganggapnya fatal.

## Kenapa izinnya belum siap

Izin node itu **sudah** diatur, di `device/oppo/A37/rootdir/etc/init.qcom.rc:149`:

```
chown system graphics /sys/class/graphics/fb0/idle_time
chmod 0664 /sys/class/graphics/fb0/idle_time
```

Tapi baris itu berada di blok `on boot` (dimulai baris 100), sementara service
composer start lebih dulu. Balapan murni. Buktinya, saat diperiksa dari perangkat
hidup node itu memang sudah `system:graphics 0664` — yang salah cuma waktunya.

## Perbaikan

Menggeser urutan di dalam `on boot` rapuh: urutannya bergantung pada urutan impor
antar berkas init, yang tidak dikendalikan device tree ini. ueventd memasang izin
saat node dibuat, sebelum service apa pun jalan, sehingga balapannya hilang
seluruhnya.

`rootdir/etc/ueventd.qcom.rc`:

```
/sys/devices/virtual/graphics/fb0    idle_time    0664    system    graphics
```

Jalurnya `/sys/devices/...` mengikuti yang tertulis di log, bukan symlink
`/sys/class/...` yang dipakai `init.qcom.rc`. Keduanya menunjuk berkas yang sama.

`hwcomposer.msm8916.so` dan `libqdutils.so` adalah blob tanpa sumber di pohon,
jadi bug `delete` mentahnya sendiri tidak bisa diperbaiki — yang dihilangkan
pemicunya.

## Hasil

Setelah flash: `/data/tombstones/` **kosong**. Sebelumnya selalu ada
`tombstone_00` di setiap boot.

---

# 2. TimeService — aplikasi yang tidak pernah bisa jalan

Ditemukan lewat buffer `events`, setelah buffer crash telanjur terhapus:

```
am_proc_start : com.qualcomm.timeservice, broadcast,
                {com.qualcomm.timeservice/.TimeServiceBroadcastReceiver}
avc: denied { read }  name="libTimeService.so"
     scontext=u:r:system_app:s0 tcontext=u:object_r:vendor_file:s0
avc: denied { open }  path="/system/vendor/lib/libTimeService.so"
am_crash      : java.lang.UnsatisfiedLinkError,
                namespace sphal does not exist or exported
am_proc_died
```

APK-nya dipasang ke `/vendor` (`soc_specific: true`) dan memuat pustaka JNI-nya
dari `/vendor` juga. Untuk itu linker memakai namespace `sphal`, yang hanya ada
kalau VNDK/Treble aktif. A37 non-Treble — build sendiri memperingatkannya:

```
build/make/core/config.mk:809: warning: This device does not have Treble enabled.
```

Jadi aplikasi ini tidak pernah bisa jalan sejak awal. Yang dihasilkannya cuma
satu proses start, satu crash, satu proses mati, setiap kali receiver-nya dipicu.

## Kenapa aman dibuang

Bukan tebakan, dua pemeriksaan:

```
$ grep -rl libTimeService /system/vendor/lib /system/vendor/bin /system/lib
/system/vendor/lib/libTimeService.so          <- hanya dirinya sendiri

$ grep -rl time_genoff /system/vendor/lib /system/vendor/bin
/system/vendor/lib/lib-imsdpl.so
/system/vendor/lib/libdrmtime.so
/system/vendor/lib/libril-qc-qmi-1.so
/system/vendor/lib/libtime_genoff.so
```

Tidak ada satu pun berkas lain yang menaut `libTimeService.so` — ia leaf yang
hanya dipakai JNI aplikasi itu. Pemakai `time_genoff` yang sesungguhnya memuat
`libtime_genoff.so` **langsung**, tanpa lewat aplikasi ini.

## Perbaikan

Dibuang dari `PRODUCT_PACKAGES` di `vendor/oppo/A37/A37-vendor.mk`, dan entrinya
dikomentari di `device/oppo/A37/proprietary-files.txt` serta
`proprietary-files-qc.txt` supaya ekstraksi ulang tidak mengembalikannya.

`libtime_genoff` dan `time_daemon` **tetap dipasang** — itu yang benar-benar
dipakai RIL dan DRM. Definisi modul di `Android.bp` sengaja dibiarkan: tanpa
entri `PRODUCT_PACKAGES` ia tidak ikut terbangun, dan blob-nya tetap tersedia
kalau device ini suatu saat dipindah ke basis ber-Treble.

Entri dikomentari, bukan dihapus, supaya jejaknya tetap terbaca.
