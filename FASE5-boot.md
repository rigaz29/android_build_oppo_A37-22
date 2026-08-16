# Fase 5 — boot

ROM terbaru: `lineage-22.2-20260816_100715-UNOFFICIAL-A37.zip` (754.028.583 B).
Riwayat boot dan akarnya ada di `DIAGNOSIS-boot1.md` .. `DIAGNOSIS-boot3.md`.

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
Batas **300 detik** (dinaikkan dari 120 pada 16 Agustus 2026), dengan **pagu
mutlak 600 detik** dan pengecualian selama `init.svc.odsign` berjalan.

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

## Boot 2 — setelah perbaikan renameat2

Boot 1 gagal: bootanimation lalu reboot ke TWRP di detik 120. Akarnya sudah
ditemukan dan diperbaiki — lihat `DIAGNOSIS-boot1.md`. Ringkasnya: `rename()`
memakai syscall `renameat2` yang tidak ada di kernel 3.10 ini, sehingga
`BOOTCLASSPATH` tidak pernah terbentuk dan zygote abort tiap 5 detik.

### Yang berubah — hanya satu hal

Sengaja **satu** perubahan saja di build ini, supaya hasilnya tidak ambigu.
Kalau beberapa perbaikan ditumpuk lalu boot berhasil, tidak akan diketahui mana
yang bekerja; kalau gagal, tidak akan diketahui mana yang merusak.

### Cara membaca hasilnya

**Kalau lolos bootanimation dan masuk homescreen** — akarnya benar dan tuntas.

**Kalau masih berputar di bootanimation**, yang pertama diperiksa adalah apakah
akar yang sama masih menggigit atau sudah bergeser ke yang lain:

```bash
adb shell ls -l /data/system/environ/          # classpath harus ADA, bukan cuma .tmp
adb shell getprop | grep -i bootclasspath      # harus terisi
```

- `classpath` **ada** → renameat2 tuntas, kegagalan berikutnya hal lain
- masih hanya `classpath.tmp` → perbaikan tidak sampai ke perangkat; periksa
  apakah zip yang di-flash benar-benar build baru (bandingkan sha256)

### Kalau boot lebih jauh tapi tetap gagal

Lima kandidat dari `tools/audit-kit21.sh` sudah disiapkan tapi **belum**
diterapkan, karena boot 1 mati sebelum `system_server` hidup sehingga kelimanya
belum pernah teruji. Daftar dan alasannya ada di `DIAGNOSIS-boot1.md`. Yang
paling perlu dicari di logcat boot berikutnya:

```bash
adb logcat -d | grep -iE 'freezer|cgroup|SensorPrivacy|ConsumerIr|BpfMap|clat'
```

Kalau ada yang muncul, patchnya sudah ada di kit dan tinggal diterapkan.

### Yang harus dikumpulkan kalau gagal lagi

Supaya satu siklus flash menghasilkan satu diagnosis utuh, kumpulkan **sekaligus**:

```bash
adb logcat -d > logcat.txt
adb shell getprop > getprop.txt
adb shell ls -lR /data/system/environ > environ.txt
adb shell dmesg > dmesg.txt
adb shell cat /sys/fs/pstore/console-ramoops-0 > console-ramoops-0
adb shell cat /sys/fs/pstore/pmsg-ramoops-0 > pmsg-ramoops-0
```

⚠️ `console-ramoops` di `report/bootfail` kemarin ternyata berasal dari sesi
**TWRP**, bukan dari boot yang gagal — jadi isinya tidak relevan. Kalau perangkat
sudah sempat masuk TWRP dan reboot lagi, pstore-nya sudah tertimpa. Ambil
pstore **sesegera mungkin** setelah kegagalan, sebelum reboot berikutnya.

Dan `dmesg` kemarin hanya mencakup dari detik ~133 karena ring buffer dibanjiri
audit SELinux permissive — jadi jangan mengandalkan `dmesg` sendirian.

---

## Boot 3 — setelah perbaikan netd BPF-less

Boot 2 gagal karena `netd` abort di `BpfHandler::init` (24 tombstone). Rincian
di `DIAGNOSIS-boot2.md`. Yang berubah di build ini **dua** hal:

1. penjaga eBPF di `bpf/netd/NetdUpdatable.cpp` — perbaikan sesungguhnya
2. bootwatchdog 120 → 300 detik — permintaan, bukan perbaikan

Keduanya sudah diverifikasi ada di zip yang dikirim lewat `tools/verify-ship.sh`.

### Gerbang penentu, urut

```bash
adb shell getprop init.svc.netd          # harus "running", BUKAN "restarting"
adb shell getprop sys.boot_completed     # 1 kalau boot benar-benar selesai
adb shell ls -l /data/system/environ/    # 'classpath' harus tetap ada
```

- `netd` **running** → akar boot 2 tuntas
- `netd` masih **restarting** → periksa apakah abortnya masih di `BpfHandler::init`;
  kalau backtrace-nya berpindah, itu akar lain
- `netd` running tapi boot tetap tidak selesai → penghalang bergeser ke tempat
  lain; kumpulkan log seperti di bawah

### Kalau boot berhasil, yang paling perlu diperiksa

```bash
adb logcat -d | grep -iE 'IdleInvalidator|RefBase.*Double owned'   # composer
adb shell getprop init.svc.vendor.hwcomposer-2-1                   # jangan "restarting"
adb logcat -d | grep -iE 'freezer|cgroup|SensorPrivacy|ConsumerIr' # kandidat audit
```

Composer sempat crash 2× di boot 2 lalu pulih. Kalau ia mulai crash-loop setelah
netd sehat, akarnya ada di `IdleInvalidator::~IdleInvalidator` (`libqdutils`)
yang dipanggil dari `qhwc::MDPComp::init`.

### Kalau gagal lagi

Kumpulkan **sekaligus**, seperti daftar di bagian Boot 2 di atas. Dua tambahan
khusus kali ini:

```bash
adb shell ls -l /sys/fs/bpf/ /sys/fs/bpf/netd_shared/ 2>&1 > bpf-fs.txt
adb logcat -d -b all > logcat-all.txt
```

`-b all` penting: logcat boot 2 kehilangan baris karena **69% isinya `avc:
denied`** dan satu proses membanjiri ring buffer. Kalau banjir itu masih ada,
ambil juga `adb logcat -d | grep -v 'avc:' > logcat-bersih.txt` supaya baris yang
berguna tidak tenggelam.

---

## Boot 4 — setelah perbaikan BPF clat

Boot 3 gagal karena `system_server` abort di `JNI_OnLoad` (`ClatCoordinator`),
12 tombstone. Rincian di `DIAGNOSIS-boot3.md`. Build ini mengubah **satu** hal:
penjaga eBPF di `verifyClatPerms()`.

```
lineage-22.2-20260816_100715-UNOFFICIAL-A37.zip   754.028.583 B
sha256 cecc42050fd6625d0fa952448b6a49f13f8afa3694fbcff706544dfe62e05048
```

### Gerbang penentu, urut

```bash
adb shell getprop sys.boot_completed              # 1 = boot selesai
adb logcat -d | grep -c 'system_server'           # harus banyak, dan TIDAK berulang mati
adb logcat -d | grep 'ClatCoordinator'            # harus sunyi, atau hanya baris "dilewati"
```

Tiga akar sebelumnya sudah tidak boleh muncul lagi:

```bash
adb shell ls -l /data/system/environ/classpath    # ada  (boot 1)
adb shell getprop init.svc.netd                   # running  (boot 2)
adb logcat -d | grep -c '>>> system_server <<<'   # 0  (boot 3)
```

### Kalau berhasil sampai homescreen

Yang paling perlu diawasi, karena sudah terlihat crash dua boot berturut-turut
lalu pulih sendiri:

```bash
adb shell getprop init.svc.vendor.hwcomposer-2-1  # jangan "restarting"
adb logcat -d | grep -iE 'IdleInvalidator|Double owned'
```

Kalau ia berubah jadi crash-loop, akarnya di `IdleInvalidator` (`libqdutils`):
turunan RefBase yang dipegang `static sp<>` sementara `getInstance()`
mengembalikan pointer mentah.

Lalu pemeriksaan fungsi yang tertunda sejak awal:

```bash
adb shell getprop ro.lineage.version
adb logcat -d | grep 'Networking module does not have permission'   # tethering
adb shell getprop init.svc.vendor.bluetooth-1-0-qti                 # jangan "restarting"
```

---

## Yang belum bisa dijawab dari mesin build

Dokumen ini **tidak** mengklaim A37 akan boot. Yang terbukti sejauh ini: seluruh
pemblokir build teratasi, ROM jadi, dan setiap perkakas diagnosis terverifikasi
ada di artefak yang dikirim. Sisanya hanya bisa dijawab perangkat.
