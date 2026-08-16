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
