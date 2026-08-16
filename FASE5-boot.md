# Fase 5 — boot

ROM siap: `lineage-22.2-20260816_071019-UNOFFICIAL-A37.zip` (754.028.285 B).

Fase ini **butuh perangkat fisik** dan tidak bisa dikerjakan dari mesin build.
Dokumen ini menyiapkan segalanya sampai batas itu.

---

## Sebelum flash

### 1. Amankan jalan pulang — kerjakan DULU

Catatan proyek 20 menyebut ROM LOS 20 **sudah tidak ada lagi di mesin build**
(terhapus saat cleanup). Satu-satunya sumber pemulihan adalah GitHub Releases:

```
lineage-20.0-20260808_130815-UNOFFICIAL-A37.zip   (615 MB)
```

Unduh dan simpan **sebelum** eksperimen berikutnya. ROM itu terbukti boot dan
dipakai sehari-hari: Wi-Fi, Bluetooth, dan RIL berfungsi.

### 2. Sadari konsekuensi keamanannya

Build ini memakai `WITH_ADB_INSECURE := true`. Terverifikasi di ROM jadi:

```
ro.adb.secure            0
persist.sys.usb.config   adb
```

Artinya **siapa pun yang mencolokkan USB mendapat shell adb tanpa dialog
otorisasi**. Itu pilihan sadar untuk perangkat uji. **Jangan dibagikan.**

---

## Perkakas diagnosis — sudah diverifikasi ADA di ROM ini

Bukan diasumsikan; diperiksa di artefak yang dikirim.

### Cmdline di `boot.img`

```
ramoops.mem_address=0x9ff00000  ramoops.mem_size=0x400000
ramoops.record_size=0x40000     ramoops.console_size=0x100000
ramoops.pmsg_size=0x40000       ramoops.dump_oops=1  ramoops.ecc=1
androidboot.selinux=permissive
androidboot.init_fatal_reboot_target=recovery
hung_task_panic=1
```

`console_size` dan `pmsg_size` eksplisit — tanpa itu defaultnya hanya 4096 byte
dan ramoops praktis tidak berguna.

### Jalur ramoops di kernel

`d4916c67ee5 pstore/ram: pulihkan jalur platform_data yang backport DT menghapusnya`
sudah ada di kernel yang dikirim. Tanpa commit ini `console-ramoops` **tidak
pernah terbentuk** — itu yang membuat seluruh saran "baca console-ramoops" di
proyek 21 sia-sia sampai akarnya ketemu.

### Pengaman boot

`/vendor/bin/bootwatchdog.sh`, dijalankan dari `init.target.rc:193`.
Batas 120 detik, dengan **pagu mutlak 600 detik** dan pengecualian selama
`init.svc.odsign` berjalan.

Pengecualian itu penting: di LOS 21 boot yang **sehat** terpotong di detik 120
karena `odrefresh` mengompilasi ulang boot classpath (81,5 detik, 190× dex2oat).
Jangan salah membaca boot pertama yang lama sebagai hang.

### Empat kelas kegagalan dan penanganannya

| Kelas | Penanganan |
|---|---|
| kernel panic | `CONFIG_PANIC_TIMEOUT=5` → reboot sendiri |
| CPU hang | `CONFIG_MSM_WATCHDOG_V2=y` → watchdog bite |
| init FATAL | `androidboot.init_fatal_reboot_target=recovery` |
| userspace menggantung | `bootwatchdog.sh` |

⚠️ Konsekuensi penting: karena panic **sudah** auto-reboot dan CPU hang **sudah**
memicu watchdog, kalau perangkat diam tanpa reboot sama sekali maka itu sudah
membuktikan **tidak ada panic dan tidak ada CPU hang**.

---

## Setelah flash — urutan pemeriksaan

### Kalau sampai homescreen

Gerbang Fase 5 tercapai. Lalu periksa yang sudah diketahui berisiko:

```bash
adb shell getprop ro.build.version.release     # 15
adb shell getprop ro.lineage.version           # 22.2-...-UNOFFICIAL-A37
adb shell getprop ro.build.product             # A37f
adb shell getprop ro.lineage.device            # A37  <- OTA
```

### Tiga hal yang PALING mungkin bermasalah, dari perubahan Fase 4

**1. Tethering.** `com.android.tethering.inprocess` **dicabut di Android 15** —
mekanisme yang di LOS 21 memperbaiki `SecurityException: MAINLINE_NETWORK_STACK`
sudah tidak ada. Belum diketahui apakah gejalanya kembali:

```bash
adb logcat -d | grep -i tethering
adb logcat -d | grep 'Networking module does not have permission'
adb shell dumpsys activity | grep -i tether
```
Gejala khasnya: Settings tampil **putih polos tanpa toolbar**, tombol Back mati.
Kalau muncul, jalur penggantinya harus dicari dari awal — **jangan** kembalikan
baris lamanya, modulnya benar-benar tidak ada.

**2. Statistik disk storaged.** Tipe `sysfs_disk_stat` dicabut agar lolos uji
beku sepolicy. `dumpsys storaged` akan kosong. Tidak memengaruhi boot.

**3. Bluetooth.** Di LOS 21 `android.hardware.bluetooth@1.0-service-qti`
crash-loop tiap 5 detik. Packaging-nya sudah diperbaiki di `lineage-21`, tapi
belum pernah diuji di 22:

```bash
adb shell getprop init.svc.vendor.bluetooth-1-0-qti   # jangan "restarting"
```

### Kalau berhenti di logo, TANPA entri USB

Ini gejala LOS 21 yang paling melumpuhkan. Urutannya:

1. **Jangan cabut baterai.** ramoops hanya bertahan pada reboot hangat; mencabut
   baterai menghapus RAM dan menghilangkan satu-satunya jejak.
2. Tunggu **minimal 600 detik** — pagu bootwatchdog. Boot pertama yang sehat
   bisa memakan 2 menit lebih hanya untuk `odrefresh`.
3. Kalau bootwatchdog bekerja, perangkat reboot sendiri ke recovery. Dari sana:
   ```bash
   adb shell ls -l /data/bootfail
   adb pull /data/bootfail
   ```
   `/data` tidak terenkripsi, jadi terbaca dari recovery.
4. Kalau tetap diam tanpa reboot: berarti **bukan** panic dan **bukan** CPU hang
   (lihat tabel di atas). Masuk TWRP dan baca pstore langsung:
   ```bash
   adb shell cat /sys/fs/pstore/console-ramoops
   adb shell cat /sys/fs/pstore/pmsg-ramoops-0
   ```

### Pelajaran instrumen dari proyek 21 — jangan diulang

- `dmesg` bisa hanya mencakup beberapa detik terakhir karena ring buffer
  dibanjiri audit SELinux permissive. **Ketiadaan pesan di dmesg bukan bukti
  bahwa sesuatu tidak berjalan.**
- Ketiadaan properti di `getprop` baru sah sebagai bukti setelah dipastikan
  `ro.boot.selinux=permissive` — kalau tidak, bisa jadi hanya `avc: denied`.
- Verifikasi selalu sampai ke artefak yang **dikirim**, bukan yang dibuat di
  `out/`. Proyek 21 sempat salah menyimpulkan fitur adb bekerja karena hanya
  memeriksa berkas yang dibuat.

---

## Yang belum bisa dijawab dari mesin build

Dokumen ini **tidak** mengklaim A37 akan boot. Yang terbukti sejauh ini: seluruh
pemblokir build teratasi, ROM jadi, dan setiap perkakas diagnosis terverifikasi
ada di artefak yang dikirim. Sisanya hanya bisa dijawab perangkat.
