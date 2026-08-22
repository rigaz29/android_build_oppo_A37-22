# Tiga denial SELinux: dua diperbaiki, satu sengaja dibiarkan

ROM ini berjalan **permissive** (`androidboot.selinux=permissive` di
`BOARD_KERNEL_CMDLINE`), pilihan sadar untuk port legacy. Konsekuensinya: setiap
denial di bawah ini dicatat tapi tidak memblokir apa pun. Semuanya laten — tidak
ada gejala yang bisa dilihat pengguna, dan baru akan menggigit kalau suatu saat
dipindah ke enforcing.

Karena itu ketiganya ditemukan lewat pemeriksaan, bukan laporan.

## Cara mengukurnya

Denial nyaris tidak muncul saat idle (0 dalam 30 detik). Ia baru terlihat kalau
subsistemnya dibebani — membuka kamera, Settings, browser, menyalakan Bluetooth.
Angka di dokumen ini semuanya dari sesi beban seperti itu.

Satu hal yang perlu disaring: perintah `adb shell` sendiri berjalan di domain
`shell` dan menghasilkan denial-nya sendiri (`comm="grep"`, `"ps"`, `"cat"`,
`"commands.monkey"`). Itu bukan temuan; itu jejak alat ukurnya.

---

# 1. gralloc — bukan salah label, salah kategori

25 dari 94 denial menunjuk satu berkas:

```
10 { getattr } for path="/system/vendor/lib/hw/gralloc.msm8916.so"
 9 { read }    for name="gralloc.msm8916.so"
 6 { open }    for path="/system/vendor/lib/hw/gralloc.msm8916.so"
```

Konteks sumbernya: `system_server` (20), `shell` (18), `platform_app` (12),
`surfaceflinger` (10), `untrusted_app` (8), `system_app` (8) — semuanya proses
yang wajar menggambar.

## Yang membatalkan dugaan pertama

Dugaan awalnya sederhana: berkas ini salah label. Pemeriksaan membatalkannya:

```
u:object_r:vendor_file:s0 /system/vendor/lib/hw/gralloc.msm8916.so
u:object_r:vendor_file:s0 /system/vendor/lib/hw/hwcomposer.msm8916.so
u:object_r:vendor_file:s0 /system/vendor/lib/hw/memtrack.msm8916.so
```

Ketiganya berlabel **sama persis**, tapi hanya gralloc yang ditolak. Jadi bukan
labelnya yang menyimpang dari tetangganya.

Yang membedakan cara pemuatannya. hwcomposer dan memtrack diakses lewat servis
binder — hanya proses servis itu yang membukanya. gralloc **di-dlopen ke dalam
proses siapa pun yang menggambar**. Untuk pola itu Android punya label khusus,
`same_process_hal_file`.

Preseden hulu memastikan ini bukan tafsir sendiri:

```
device/qcom/sepolicy-legacy-um/legacy/vendor/msm8996/file_contexts:105
device/qcom/sepolicy-legacy-um/legacy/vendor/msm8937/file_contexts:61
```

Keduanya melabeli `gralloc.<platform>.so` sebagai `same_process_hal_file`.
Berkas platform hulu tidak mencakup msm8916, jadi A37 tidak ikut kebagian.

Penguat terakhir ada di berkas hasil build sendiri — tiga anggota keluarga
gralloc lain sudah berlabel benar dari hulu:

```
libgralloctypes.so   -> same_process_hal_file
libgrallocutils.so   -> same_process_hal_file
gralloc.default.so   -> same_process_hal_file
gralloc.msm8916.so   -> vendor_file          <- satu-satunya yang tertinggal
```

## Perbaikannya tidak selesai di satu tempat

Setelah gralloc dilabeli, denial turun 94 → 23. Tapi yang tersisa memperlihatkan
sesuatu:

```
avc: denied { read } for name="libmemalloc.so"
     scontext=u:r:untrusted_app:s0 tcontext=u:object_r:vendor_file:s0
     app=org.lineageos.aperture
```

`libmemalloc.so` ada di `DT_NEEDED` gralloc. Saat aplikasi memuat gralloc, linker
ikut menarik dependensinya — dengan konteks aplikasi itu sendiri. Selama labelnya
`vendor_file`, masalahnya cuma **berpindah satu tingkat ke bawah**.

Pelajarannya: untuk same-process HAL, yang harus dilabeli adalah seluruh closure
dependensinya, bukan pustaka teratasnya saja. Dependensi vendor gralloc ada tiga,
dan dua di antaranya ternyata sudah benar tanpa perlu disentuh:

```
libmemalloc.so     vendor_file             <- diperbaiki
libqdMetaData.so   same_process_hal_file   <- sudah benar dari sepolicy QCOM hulu
libqdutils.so      same_process_hal_file   <- sudah benar dari sepolicy QCOM hulu
```

`libmemalloc` tidak ikut terlabeli hulu karena ia khas era msm8916 — alasan yang
sama persis dengan `gralloc.msm8916.so` sendiri.

Sisa denial setelah keduanya: `qemu_sf_lcd_density_prop` (properti emulator,
tidak relevan) dan beberapa node sysfs sensor.

---

# 2. Alamat Bluetooth tidak akan bertahan di bawah enforcing

```
avc: denied { set } for property=persist.vendor.service.bdroid.bdaddr
     pid=693 uid=1002 scontext=u:r:hal_bluetooth_qti:s0
     tcontext=u:object_r:vendor_default_prop:s0 tclass=property_service
```

Properti itu tidak punya label, jadi jatuh ke `vendor_default_prop`. Sekarang
alamatnya tetap tersimpan — `80:58:f8:c1:02:c4`, cocok dengan yang dipakai
sistem — justru **karena** permissive. Di bawah enforcing set-nya ditolak dan
alamat BT berubah tiap boot.

Hulu melabeli varian non-vendor sebagai `bluetooth_prop`:

```
system/sepolicy/private/property_contexts:86
  persist.service.bdroid.    u:object_r:bluetooth_prop:s0
```

HAL QCOM di perangkat ini memakai varian **vendor**, yang tidak tercakup entri itu.

## Kenapa tidak memakai `bluetooth_prop` langsung

Tipe core tidak pantas menaungi namespace `persist.vendor.*`. Dipakai tipe vendor
tersendiri, mengikuti pola yang sudah ada di device tree ini
(`vendor_timekeep_prop`) — tiga bagian, tidak lebih:

```
sepolicy/property.te         type vendor_bluetooth_prop, property_type;
sepolicy/property_contexts   persist.vendor.service.bdroid. -> vendor_bluetooth_prop
sepolicy/bluetooth.te        set_prop(hal_bluetooth_qti, vendor_bluetooth_prop)
```

Rantai izinnya sendiri sudah ada dan tidak perlu disentuh:

```
device/qcom/sepolicy-legacy/common/hal_bluetooth_qti.te:29
  hal_server_domain(hal_bluetooth_qti, hal_bluetooth)

system/sepolicy/private/hal_bluetooth.te:28
  set_prop(hal_bluetooth, bluetooth_prop)
```

Domainnya memang berhak menyetel properti Bluetooth. Yang bolong hanya labelnya.

---

# 3. storaged — sengaja dibiarkan

```
avc: denied { read } for comm="storaged" name="stat"
     path="/sys/devices/soc.0/7824900.sdhci/mmc_host/mmc0/mmc0:0001/block/mmcblk0/stat"
     scontext=u:r:storaged:s0 tcontext=u:object_r:sysfs:s0
```

Ini hampir diperbaiki. `storaged` memang membaca node itu by design:

```
system/core/storaged/include/storaged_diskstats.h:27
  #define MMC_DISK_STATS_PATH "/sys/block/mmcblk0/stat"
```

(`/sys/block/mmcblk0` symlink ke jalur platform di atas, karena itu jalur yang
muncul di denial berbeda dari yang ada di sumber.)

Dugaan pertama: relabel ke `sysfs_devices_block`. Itu **tidak akan menyelesaikan
apa pun** — label tersebut hanya boleh dibaca `dumpstate` dan `vold`, jadi yang
berubah cuma label yang ditolak.

Yang membatalkannya sepenuhnya adalah `system/sepolicy/private/storaged.te`
selengkapnya: **tidak ada satu pun aturan** yang memberi storaged akses baca ke
sysfs block stat, baik `sysfs` maupun `sysfs_devices_block`. Yang diizinkan hanya
`proc_uid_io_stats`, `system_data_file`, `packages_list_file`, dan
`debugfs_mmc` (itu pun hanya pada build userdebug/eng).

Jadi denial ini perilaku AOSP normal di semua device, bukan cacat A37.

Dan port ini memang menegaskannya. Di antara patch kit ada:

```
patches/system_sepolicy/0601-Revert-Fix-storaged-access-to-sys-block-mmcblk0-stat.patch
```

Akses storaged ke node itu **sengaja di-revert**. Menambah aturan device-specific
justru akan melawan keputusan yang sudah diambil.

---

## Catatan untuk pemeriksaan berikutnya

Jangan memverifikasi label dengan pola yang mengandung titik tanpa `-F`. Di
berkas `file_contexts` jalurnya ditulis sebagai regex — `gralloc\.msm8916\.so`.
Pola `grep 'gralloc.msm8916'` tidak akan cocok, karena titik sebagai wildcard
hanya menutup satu karakter sedangkan di sana ada dua (`\` dan `.`). Kekeliruan
ini sempat menghasilkan kesimpulan salah bahwa label gagal masuk image.

Jangan pula mengambil nomor baris dari keluaran yang sudah disaring. Isi
`hal_bluetooth_qti.te` dibaca dengan `grep -vE '^\s*$|^\s*#'` untuk membuang
komentar, lalu nomor barisnya dihitung dari tampilan itu — menghasilkan `:2`,
padahal di berkas aslinya `hal_server_domain(hal_bluetooth_qti, hal_bluetooth)`
ada di **baris 29**. Nomor yang salah itu terlanjur ikut ke pesan commit
`5792a101`; yang benar tercatat di dokumen ini. Pakai `grep -n` pada berkas utuh,
bukan menghitung dari hasil filter.
