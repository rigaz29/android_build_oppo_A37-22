# Boot 1 — bootanimation lalu reboot ke TWRP di detik 120

Artefak: `report/bootfail/` (logcat 2,1 MB, pmsg-ramoops, getprop, environ).
ROM: `lineage_A37-userdebug 15 BP1A.250505.005`.

**Akar: `renameat2` tidak ada di kernel 3.10 A37. Terkonfirmasi, bukan dugaan.**

---

## Rantai sebab, tiap mata rantai berbukti

**1. Berkas yang seharusnya ada, tidak ada** — `environ.txt`:

```
classpath.tmp   4439 B      <- ada
classpath                   <- TIDAK ADA
```

**2. Konsumen berkas itu abort** — `logcat.txt`:

```
F DEBUG : Abort message: 'BOOTCLASSPATH is not defined.'   (odrefresh --check, pid 438, SIGABRT)
F zygote: file_utils.cc:527] Check failed: !location.empty()
          BOOTCLASSPATH and DEX2OATBOOTCLASSPATH must not be empty
```
berulang tiap ~5 detik sampai bootwatchdog memotong di detik 120.

**3. Produsennya jalan dan keluar normal** — `getprop.txt`:

```
init.svc.derive_classpath   stopped
ro.boottime.derive_classpath 16449618967    <- selesai di detik 16,4
apexd.status                ready           <- APEX sehat, bukan itu masalahnya
```

**4. Kenapa `.tmp` ada tapi tujuannya tidak** — `derive_classpath.cpp:165-173`:

```cpp
if (android::base::StartsWith(path_str, "/data/")) {
  const std::string temp_str(path_str + ".tmp");
  if (!android::base::WriteStringToFile(content, temp_str, true)) return false;
  return rename(temp_str.c_str(), path_str.c_str()) == 0;   // <- gagal di sini
}
```

Tulis berhasil (4439 B nyata), `rename()` gagal.

**5. Kenapa `rename()` gagal** — bionic hulu:

```cpp
int rename(const char* old_path, const char* new_path) {
  return renameat2(AT_FDCWD, old_path, AT_FDCWD, new_path, 0);
}
```
`libc/SYSCALLS.TXT:164` hanya punya `renameat2`; `renameat` polos tidak diekspor
sebagai syscall.

**6. Kenapa `renameat2` gagal** — kernel A37, `arch/arm64/include/asm/unistd32.h:788`:

```c
/* #define __NR_renameat2 382 */     <- DIKOMENTARI
```
Nomornya disediakan, implementasinya tidak pernah masuk; `fs/namei.c` tidak punya
`SYSCALL_DEFINE5(renameat2)`. Tetangganya justru **di-backport** — `seccomp` 383,
`getrandom` 384, `memfd_create` 385 — jadi ini kelalaian backport yang spesifik,
bukan kernel yang seragam tua.

**7. Konfirmasi independen** — gejala di dua proses lain yang tidak berhubungan
dengan classpath, dua-duanya `rename()` ke `/data`:

```
E vold    : Failed to rename /data/media/obb.new to /data/media/obb: Function not implemented
E installd: Failed to save version to /data/misc/installd/layout_version: Function not implemented
```

"Function not implemented" = **ENOSYS**. Syscall hilang, bukan izin, bukan SELinux.

---

## Perbaikan

`renameat` polos **ada** di kernel ini — `__NR_renameat 329`, terimplementasi di
`fs/namei.c:4022`. Jadi arahkan `rename()` ke sana.

Patch: `patches/bionic/0801-A37-revert-Rewrite-renameat-*.patch`, diambil utuh
dari kit LOS 21, terap bersih ke fork ULH. Hasil:

```cpp
int rename(const char* old_path, const char* new_path) {
  return renameat(AT_FDCWD, old_path, AT_FDCWD, new_path);
}
```
`SYSCALLS.TXT` kini mengekspor **keduanya** — `renameat` (dipakai) dan `renameat2`
(tetap ada demi kompatibilitas API, hanya akan ENOSYS kalau benar-benar dipanggil).

---

## Kenapa ini lolos, dan apa yang berubah

Fork ULH `bionic` di 22.2 **tidak** membawa revert ini, padahal LOS 21 sudah
mendiagnosis kegagalan yang identik dan menyimpan patchnya. Ini **kelalaian
ketiga** dengan pola yang sama persis, setelah `String8::string()` dan `zip -y`:
patch sudah ada, terap bersih, dan tetap ditunggu sampai gerbang menabraknya.

Dua yang pertama menelan satu siklus build (~1 jam). Yang ini menelan satu siklus
build **plus satu siklus flash fisik** — ongkos yang hanya bisa dibayar pengguna,
bukan mesin build.

Penanggulangannya bukan "lain kali lebih teliti" melainkan alat:
**`tools/audit-kit21.sh`** menguji seluruh 138 patch kit LOS 21 terhadap pohon 22
secara mekanis, baca-saja, dalam hitungan detik. Hasil pada pohon saat ini:

```
SUDAH ada di pohon      : 23
ABSEN (hunk tidak ada)  : 33
BEDA (konteks bergeser) : 82
```

Ketiga patch yang terlewat itu semuanya akan muncul sebagai **ABSEN**.

---

## Verifikasi — dan dua jebakan yang hampir menipu

Tanda tangan yang dicari sudah ditetapkan LOS 21: `rename()` harus melompat ke
`renameat`. Hasil dari **zip yang dikirim** (`...075124...`, 753.900.022 B,
sha256 `40bc7fd5fa953ce9...`):

```
65a30: mvn   r0, #0x63                                  <- -100 = AT_FDCWD
65a38: b.w   0xb147c <__ThumbV7PILongThunk_renameat>    <- bukan renameat2

a3704: movw  r7, #0x149                                 <- 0x149 = 329
a3708: svc   #0x0
```

Dua gerbang, dua-duanya lolos: `rename()` memang menuju `renameat`, dan
`renameat` memang stub syscall sungguhan bernomor **329** — persis
`__NR_renameat` yang ada di kernel ini. Nomor itu hanya terbentuk kalau
`SYSCALLS.TXT` mengekspornya, jadi ia sekaligus membuktikan patchnya masuk.

Tapi tiga hal hampir menghasilkan kesimpulan yang salah:

**1. Stempel waktu berbohong.** `out/target/product/A37/system/lib/libc.so`
bertanggal **15 Agustus 22:05** — lebih tua dari patchnya — yang tampak seperti
bukti kuat bahwa libc tidak dibangun ulang. Kenyataannya intermediate bionic
dibangun ulang jam **07:55:28**. Berkas di `/system/lib/libc.so` bahkan bukan
ELF sama sekali melainkan **symlink 44 byte** ke
`/apex/com.android.runtime/lib/bionic/libc.so`.

**2. Membongkar berkas yang salah balik kosong, bukan salah.** Karena target di
atas symlink, `objdump` menghasilkan nol baris. Dibaca sekilas, "tidak ada
renameat2" gampang disalahartikan sebagai lolos. Verifikator karena itu memaksa
`exit 1` kalau target lompatan tidak terbaca — **diam bukan lulus.**

**3. `debugfs` tidak bisa membaca Android sparse image.** Gejalanya menyesatkan:
`ls /` balik kosong dan setiap path tampak tidak ada, seolah isi image-nya salah
padahal cuma formatnya. Verifikator kini mendeteksi magic `3aff26ed` dan
menjalankan `simg2img` lebih dulu.

Dan libc sungguhan ternyata terkubur **tiga lapis**, masing-masing format berbeda:

```
system.img (ext4)
  └─ /system/apex/com.android.runtime.apex (ZIP)
       └─ apex_payload.img (ext4 TERSEMAT)
            └─ /lib/bionic/libc.so        <- yang benar-benar dipakai
```

Lapis kedua sempat dikira zip biasa yang memuat libc langsung; ternyata isinya
`apex_payload.img`. Jalur penuh yang ditempuh `tools/verify-rename.sh`:
`zip → brotli → sdat2img → simg2img → debugfs → APEX zip → payload ext4 → objdump`.

---

## Kandidat ABSEN yang relevan untuk boot berikutnya

**Sengaja TIDAK diterapkan sekarang.** Build ini menguji satu hipotesis; menumpuk
perubahan lain akan mengaburkan hasilnya.

| Patch | Kenapa dicurigai |
|---|---|
| `system_core/0004-Revert-libprocessgroup-switch-freezer-to-cgroup-v2` | kernel 3.10 tidak punya cgroup v2 |
| `frameworks_base/0020-Don-t-crash-if-there-is-IR-HAL-is-not-declared` | bisa mematikan `system_server` |
| `frameworks_base/0022-Hack-Ignore-SensorPrivacyService-Security-Exception` | idem |
| `Connectivity/0015-UL-libnetworkstats-Make-use-of-BpfMap-safe` | jalur BPF-less |
| `Connectivity/0011-UL-clatcoordinator-Support-no-bpf-usecase` | jalur BPF-less |

⚠️ Pencarian kata kunci di `logcat.txt` boot gagal ini menghasilkan **nol** untuk
`freezer`, `cgroup`, `SensorPrivacy`, `IR HAL`, `BpfMap`, dan `clat`. Itu **bukan**
bukti bahwa kelimanya tidak diperlukan: zygote abort sebelum `system_server`
pernah hidup, jadi kode tersebut memang belum sempat berjalan. Nol di sini berarti
**belum teruji**, bukan **tidak bermasalah** — persis jebakan "ketiadaan pesan
bukan bukti" yang sudah tercatat di `FASE5-boot.md`.

Kelimanya baru bisa dinilai dari boot **berikutnya**, setelah zygote lolos.
