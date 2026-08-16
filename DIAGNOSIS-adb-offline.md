# adb USB `offline` — FunctionFS tanpa AIO

Gejala: `adb devices` menampilkan serial perangkat dengan status **`offline`**,
bukan `unauthorized`. Perangkat lain (Pixel 8) normal di host yang sama, dan ROM
**LOS 20 di A37 ini juga normal** — jadi host, kabel, dan driver bersih.

`offline` (bukan `unauthorized`) berarti perangkat ter-enumerasi di USB tapi
handshake protokol adb tidak pernah selesai. Otorisasi bahkan belum jadi
pertanyaan.

## Akar

Kernel 3.10 perangkat ini menyediakan FunctionFS lewat **gadget Android lama**,
bukan `CONFIG_USB_FUNCTIONFS`:

```
drivers/usb/gadget/android.c:39   #include "f_fs.c"
.config                           # CONFIG_USB_FUNCTIONFS is not set
                                  CONFIG_USB_G_ANDROID=y
```

Dan `f_fs.c` versi itu punya **nol** dukungan AIO:

```
grep -cE 'aio_|io_submit|kiocb' drivers/usb/gadget/f_fs.c   ->  0
```

Sementara adbd Android 15 di pohon 22 hanya punya satu jalur:

```cpp
void usb_init() {
    std::thread(usb_ffs_open_thread).detach();   // io_submit, tanpa syarat
}
```

`daemon/usb.cpp:590` memanggil `io_submit()` pada endpoint FFS. Tanpa dukungan
AIO di kernel, panggilan itu gagal, `HandleError` menghancurkan transport,
`UsbFfsConnection` ikut hancur, dan seluruh proses diulang dari awal — selamanya.
Endpoint terbentuk, deskriptor tertulis, gadget `CONFIGURED`, tapi **data tidak
pernah mengalir**.

Deskriptor **bukan** masalahnya: kernel hanya mengenal
`FUNCTIONFS_DESCRIPTORS_MAGIC` (V1), tapi `daemon/usb_ffs.cpp:282-294` sudah
punya jalur mundur — tulis V2 dulu, kalau gagal tulis V1.

## Yang paling menentukan

**Device tree ini sudah menyetel perbaikannya sejak awal.**
`rootdir/etc/init.qcom.usb.rc:55-56`:

```
setprop persist.adb.nonblocking_ffs 0
setprop ro.adb.nonblocking_ffs 0
```

Warisan dari LOS 20, tempat adb berfungsi. Tapi Android 15 mencabut implementasi
FunctionFS legacy **beserta pembacaan propertinya**, sehingga dua baris itu
menjadi mubazir — diset dengan benar, tidak dibaca siapa pun, dan tidak
meninggalkan jejak apa pun di log.

Itu sebabnya gejalanya tampak tidak masuk akal: konfigurasi perangkat benar,
semua yang bisa diperiksa tampak sehat, dan tetap tidak berfungsi.

## Perbaikan

Port patch LOS 21 `packages_modules_adb/0001-adb-Bring-back-support-for-legacy-FunctionFS`
ke pohon 22. Yang dipulihkan:

```cpp
void usb_init() {
    bool use_nonblocking = GetBoolProperty("persist.adb.nonblocking_ffs",
                           GetBoolProperty("ro.adb.nonblocking_ffs", true));
    if (use_nonblocking) std::thread(usb_ffs_open_thread).detach();
    else                 usb_init_legacy();          // jalur blocking, tanpa AIO
}
```

Ditambah deteksi runtime sebagai lapis kedua: `io_submit` gagal dengan `EINVAL`
-> `gFfsAioSupported=false` -> alih ke `usb_init_legacy()`.

Dan `device.mk` kini menuliskan propertinya ke `build.prop`, bukan hanya lewat
`setprop` di `on fs`. Properti `ro.` dari `build.prop` sudah ada sebelum aksi
init mana pun berjalan, jadi tidak ada lagi ketergantungan urutan.

### Penyesuaian yang tidak ada di patch asli

Patch LOS 21 menaruh `transport_legacy.cpp` di `libadb_srcs` — daftar yang
dipakai bersama. Di pohon 22 itu **tidak boleh**: `libadb_host` juga memakai
daftar itu dan sudah memuat `client/transport_usb.cpp`, yang mendefinisikan
`init_usb_transport` persis seperti `transport_legacy.cpp` (dan keduanya tidak
berpenjaga prapemroses). Hasilnya simbol ganda di build host.

Di sini `transport_legacy.cpp` ditaruh di daftar `srcs` milik target adbd saja.

## Kenapa ini bukan pengulangan kegagalan LOS 21

LOS 21 menghadapi gejala yang sama dan **tidak terpecahkan**. Catatannya
menyimpulkan sisi perangkat bersih dan menandai `usb_legacy.cpp` non-AIO sebagai
"tersangka tersisa".

Bedanya: seluruh catatan LOS 21 **tidak pernah menyebut `nonblocking_ffs` sama
sekali**. Mereka bergantung pada deteksi runtime, yang hanya bekerja kalau
kegagalan `io_submit` benar-benar muncul sebagai `EINVAL` di titik yang
diperiksa. Jalur properti memaksa keputusan sebelum satu panggilan AIO pun
dicoba, jadi tidak bergantung pada bentuk kegagalannya.

Itu tetap **belum tentu cukup**. Kalau jalur legacy sendiri yang bermasalah,
gejalanya akan sama persis.

## Verifikasi

Metode dari LOS 21, dipakai ulang di `tools/verify-ship.sh`: hitung string di
biner adbd yang dikirim.

```
adbd ROM LOS 20 (adb BERFUNGSI)   usb_legacy=3  transport_legacy=2
build LOS 21 yang offline         usb_legacy=0  transport_legacy=0
```

Ditambah gerbang kedua: `ro.adb.nonblocking_ffs=false` harus ada di `build.prop`.

## Hasil build

```
lineage-22.2-20260816_112357-UNOFFICIAL-A37.zip   754.101.564 B
sha256 b7eb3c9cbacf76ad8230ecd0f6fd5f52105f9c84a01f4e77fea686fa38ed2ce2
```

Diverifikasi dari zip yang dikirim, menembus APEX com.android.adbd:

```
usb_legacy=3  transport_legacy=2      <- cocok persis dengan ROM LOS 20
ro.adb.nonblocking_ffs=false          <- ada di build.prop
```

⚠️ Kompilasi pertama sempat menyesatkan: `m adbd` membangun varian **linux_glibc**
(adbd host), yang justru memakai `usb_dummy.cpp` dan tidak pernah menyentuh
`usb_legacy.cpp`. Build itu lolos tanpa membuktikan apa pun. Varian perangkat
harus diminta terpisah lewat `m com.android.adbd`.

## Kalau masih offline setelah ini

Perangkat sudah boot ke homescreen, jadi diagnosis tidak lagi bergantung pada
adb. Yang paling menjelaskan, lewat aplikasi terminal di perangkat:

```
getprop | grep nonblocking_ffs        # harus false/0
logcat -s adbd:V                      # dengan kabel tercolok
getprop persist.adb.trace_mask        # usb,transport
```

Kalau `usb_init` sudah mengambil jalur legacy tapi data tetap tidak mengalir,
barulah tersangka LOS 21 (jalur baca/tulis legacy itu sendiri) menjadi relevan —
dan saat itu jejaknya akan terlihat di `logcat -s adbd:V`, yang di LOS 21 tidak
pernah sempat terkumpul.
