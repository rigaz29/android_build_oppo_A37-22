# Rencana build LineageOS 22.2 (Android 15) — OPPO A37 / A37f

**Perangkat:** OPPO A37 — Qualcomm MSM8916 (Snapdragon 410), Adreno 306, 2 GB RAM
**Kernel:** 3.10.108, **arm64**, defconfig `lineageos_a37f_defconfig` (680 baris)
**Userspace:** `TARGET_ARCH := arm` (armeabi-v7a, armv8-a, cortex-a53) — 32-bit di atas kernel 64-bit
**Basis yang diminta:** kernel `rigaz29/kernel_oppo_msm8939` @ `lineage-20`, device tree `rigaz29/rb_device_oppo_A37` @ `lineage-20`

> Dokumen ini dibangun dari pembacaan kode, bukan asumsi. Setiap klaim yang menentukan
> keputusan diikat ke berkas dan baris yang bisa diperiksa ulang. Bahan yang dipakai ada di
> §2 beserta lokasinya di mesin.

---

## 0. Vonis singkat

**Bisa dikerjakan, dan lebih murah dari LOS 21.** Alasannya bukan optimisme melainkan tiga
fakta terukur:

| | Temuan | Bukti |
|---|---|---|
| 1 | Pemblokir terbesar LOS 21 — RenderEngine GLES — **sudah tersedia di basis 22.2** | `ULH/android_frameworks_native@lineage-22.2` punya `libs/renderengine/gl/GLESRenderEngine.cpp` (HTTP 200); `LineageOS/…@lineage-22.2` **404** |
| 2 | Kamera **tidak lagi butuh restorasi `device1/` di frameworks_av** | acroreiser mengganti jalurnya dengan `hal3on1` yang membangun ulang `camera.$(TARGET_BOARD_PLATFORM)` sebagai modul HAL3 — `ref/device_a6010/camera/hal3on1/Android.mk` |
| 3 | Versi policydb SELinux **pas, tanpa backport kernel** | LOS 22.2 mengompilasi `PolicyVers = 30` (`system/sepolicy/build/soong/policy.go:31`); kernel A37 `POLICYDB_VERSION_MAX = POLICYDB_VERSION_XPERMS_IOCTL = 30` (`security/selinux/include/security.h:37,44`) |

**Pekerjaan kernel hampir kosong.** Sama seperti kesimpulan Anda di LOS 21, Android 15
tidak menuntut satu pun *fitur* kernel baru yang wajib di atas Android 14. Yang tersisa
adalah **satu patch dua-berkas** (§4.2) — kecil, tapi kali ini benar-benar wajib, berbeda
dari LOS 21 di mana kernel bisa dibiarkan utuh.

**Yang berubah paling besar justru basisnya.** `LineageOS-UL` berhenti di `lineage-21.0`.
Penerusnya untuk 22/23 adalah org **`Ultra-Legacy-Hippeastrum`** (dibuat 2025-04-30), dan
modelnya **berbeda** dari UL: bukan satu manifest `android` yang menggantikan semuanya,
melainkan **fork per-repo** dengan branch `lineage-22.2` yang Anda pasang lewat local
manifest di atas manifest LineageOS resmi.

---

## 1. Apa yang berubah dari LOS 21 → LOS 22, dari sudut A37

| Aspek | LOS 21 (yang Anda kerjakan) | LOS 22.2 (rencana ini) |
|---|---|---|
| Basis legacy | `repo init` ke `LineageOS-UL/android -b lineage-21.0` (1453 project, 174 GB) | `repo init` ke **LineageOS resmi** `-b lineage-22.2` (969 project) + local manifest yang menimpa ~13 repo dengan fork ULH |
| RenderEngine GLES | 9 patch, 14.464 baris, port tangan | **Sudah ada di fork ULH** |
| Kamera | Restorasi `device1/` + `CameraClient` di frameworks_av (4 berkas ±98 KB + ±200 baris adaptasi) | **`hal3on1`** — adapter 95 KB satu berkas di device tree, tidak menyentuh frameworks_av |
| HAL qcom-caf msm8916 | `LineageOS-UL/…@lineage-21.0-caf-msm8916` (dipakai di manifest LOS 21 Anda) | Branch itu **tidak punya penerus**: UL berhenti di 21.0, ULH hanya menyediakan `lineage-22.2-caf-msm8952`. Lihat §5.2 |
| BPF | Ditambal tangan (2 patch buatan sendiri di `packages/modules/Connectivity`) | Set patch BPF-less **yang terawat** untuk 22.2: `MisterZtr/LineageOS_gsi@lineage-22.2` |
| ART `memfd_create` | Patch UL `art/0001-…` (tersedia di basis UL) | ULH **tidak menyediakan fork `art` di 22.2** → harus dibawa sendiri, lihat §4.2 |
| Radio HAL | 1.1 | a6010 pindah ke **1.4** lewat wrapper in-tree (opsional bagi A37 — lihat §5.4) |

---

## 2. Bahan yang sudah diunduh (dan di mana)

Semua di `/root/a37-22`, total 3,9 GB. **Ini bukan `repo sync` penuh** — pohon LOS 22.2
utuh berukuran ~200 GB dan disinkronkan di Fase 0. Yang diunduh di sini adalah bahan
analisis yang cukup untuk mengunci setiap keputusan di dokumen ini.

| Jalur | Isi | Guna |
|---|---|---|
| `base/kernel_a37` (1,8 GB) | `rigaz29/kernel_oppo_msm8939`, semua branch | Basis kernel yang diminta (`lineage-20`) |
| `base/device_A37` (65 MB) | `rigaz29/rb_device_oppo_A37`, semua branch | Basis device tree (`lineage-20`, dan `lineage-21` untuk pembanding) |
| `base/android_build_oppo_A37-{20,21}` | Kit build Anda sendiri | Riwayat jebakan yang sudah terpetakan |
| `ref/kernel_a6010` (2,0 GB) | `acroreiser/android_kernel_lenovo_a6010` | **Jangkar utama**: msm8916 + 3.10.108 yang benar-benar menjalankan LOS 22.2 |
| `ref/device_a6010` (111 MB) | Device tree a6010, branch `lineage-22.2` | Pola device tree A15 untuk msm8916 |
| `ref/ulh_patches` | `Ultra-Legacy-Hippeastrum/legacy_support_patches` | Konteks — **hanya punya branch `lineage-23.2`**, lihat §3.3 |
| `ref/ulh_caf_common` | Fork ULH `hardware/qcom-caf/common` @ 22.2 | |
| `los22/manifest_los22` | `LineageOS/android` @ `lineage-22.2` (969 project) | Sumber path project untuk local manifest |
| `los22/gsi_patches` | `MisterZtr/LineageOS_gsi` @ `lineage-22.2` — **193 patch** di 25 repo | Set patch legacy/BPF-less |
| `analysis/` | Log & diff terklasifikasi | Angka-angka di §4 |

⚠️ `repo` **belum terpasang** di mesin ini, dan RAM 11 GB berada di bawah kebutuhan nyaman
build Android 15 (≈16 GB+). Keduanya masuk Fase 0.

---

## 3. Peta basis LOS 22.2

### 3.1 Perintah init

```bash
repo init -u https://github.com/LineageOS/android.git -b lineage-22.2 --git-lfs
```

Berbeda dari LOS 21: **bukan** `LineageOS-UL/android`. Org itu tidak punya branch di atas
`lineage-21.0` (diperiksa: `LineageOS-UL/android` → `lineage-19.1, lineage-20.0, lineage-21.0`).

### 3.2 Fork ULH yang menimpa repo resmi

Diverifikasi lewat `ls-remote` — hanya yang benar-benar punya branch `lineage-22.2`:

| path di pohon | ganti ke | branch | kenapa |
|---|---|---|---|
| `frameworks/native` | `Ultra-Legacy-Hippeastrum/android_frameworks_native` | `lineage-22.2` | **RenderEngine GLES** — tanpa ini Adreno 306 dipaksa Skia |
| `frameworks/base` | `…/android_frameworks_base` | `lineage-22.2` | |
| `system/core` | `…/android_system_core` | `lineage-22.2` | |
| `bionic` | `…/android_bionic` | `lineage-22.2` | |
| `system/sepolicy` | `…/android_system_sepolicy` | `lineage-22.2` | |
| `device/qcom/sepolicy` | `…/android_device_qcom_sepolicy` | **`lineage-22.2-legacy`** | perhatikan akhiran `-legacy` |
| `hardware/qcom-caf/common` | `…/android_hardware_qcom-caf_common` | `lineage-22.2` | |
| `system/libhidl` | `…/android_system_libhidl` | `lineage-22.2` | |
| `system/libhwbinder` | `…/android_system_libhwbinder` | `lineage-22.2` | di manifest resmi ini repo **AOSP**, bukan LineageOS |
| `hardware/ril` | `…/android_hardware_ril` | `lineage-22.2` | |
| `hardware/qcom-caf/msm8916/audio` | `…/android_hardware_qcom_audio` | `lineage-22.2-caf-msm8952` | msm8952, **bukan** 8916 — lihat §5.2 |
| `hardware/qcom-caf/msm8916/display` | `…/android_hardware_qcom_display` | `lineage-22.2-caf-msm8952` | idem |
| `hardware/qcom-caf/msm8916/media` | `…/android_hardware_qcom_media` | `lineage-22.2-caf-msm8952` | idem |

### 3.3 Yang ULH **tidak** sediakan di 22.2 — dan penggantinya

Ini bagian yang paling mudah salah dibaca, jadi ditulis eksplisit. Repo berikut punya fork
ULH **hanya di `lineage-23.2`**, tidak di 22.2:

`frameworks/av` · `packages/modules/Connectivity` · `device/lineage/sepolicy` ·
`system/tools/mkbootimg` · `packages/apps/Updater` · `hardware/broadcom/wlan`

Dan `Ultra-Legacy-Hippeastrum/legacy_support_patches` — yang README-nya menjelaskan alur
"clone LineageOS lalu jalankan `apply.sh`" — **hanya punya branch `lineage-23.2`**
(commit pertama 2026-03-01). README-nya menuntut branch patch = branch target, jadi
**tidak dipakai untuk 22.2.**

**Penggantinya untuk 22.2: `MisterZtr/LineageOS_gsi` branch `lineage-22.2`** — 193 patch di
25 repo, termasuk seluruh jalur BPF-less. README ULH sendiri yang menunjuk ke sana:

> NOTE: THESE PATCHES DO NOT COVER BPF-LESS DEVICES! If your kernel BPF level is lower
> than 5.4 additionally try to apply bpf patches from
> `https://github.com/MisterZtr/LineageOS_gsi/tree/lineage-23.2/patches/trebledroid`

### 3.4 Enam project tambahan LOS 21 — statusnya di 22.2

Manifest LOS 21 Anda (`A37-21.xml`) membawa enam project di luar device/kernel/vendor.
Nasib masing-masing di 22.2, diperiksa satu per satu:

| project LOS 21 | path | status di 22.2 |
|---|---|---|
| `LineageOS-UL/…_qcom_audio` @21.0-caf-msm8916 | `hardware/qcom-caf/msm8916/audio` | **tak ada penerus** → §5.2 |
| `LineageOS-UL/…_qcom_display` @21.0-caf-msm8916 | `…/display` | **tak ada penerus** → §5.2 |
| `LineageOS-UL/…_qcom_media` @21.0-caf-msm8916 | `…/media` | **tak ada penerus** → §5.2 |
| `LineageOS-UL/…_device_qcom_sepolicy` @21.0-legacy | `device/qcom/sepolicy-legacy` | ✅ **ULH `lineage-22.2-legacy`** — penerus langsung. Wajib: `BoardConfig.mk:580` meng-`include device/qcom/sepolicy-legacy/sepolicy.mk` |
| `LineageOS-UL/…_system_tools_dtbtool` @21.0 | `system/tools/dtbtool` | ⚠️ **tak ada penerus di mana pun** (LineageOS resmi tidak punya branch 21/22 sama sekali) — **tapi tidak dibutuhkan**: `TARGET_CUSTOM_DTBTOOL := dtbToolOppo` (`BoardConfig.mk:302`) dilayani device tree sendiri lewat `dtbtool/Android.bp:27`. **Buang dari manifest 22.** |
| `LineageOS/…_hardware_sony_timekeep` @21 | `hardware/sony/timekeep` | ✅ **`lineage-22.2` ada** — pakai apa adanya |

Jadi dari enam, **satu hilang tanpa perlu diganti**, **dua punya penerus langsung**, dan
**tiga (HAL msm8916) adalah pekerjaan sungguhan** — itulah §5.2.

Perhatikan juga: manifest LOS 22.2 resmi sudah membawa
`device/qcom/sepolicy-legacy-um` (`snippets/lineage.xml:89`, revisi
`lineage-22.2-legacy-um`) untuk grup `sdm660`. Itu **path berbeda** dari
`sepolicy-legacy`, jadi tidak bertabrakan — tapi jangan tertukar.

---

## 4. KERNEL — inti dokumen ini

### 4.1 Keadaan kernel A37 sekarang (terukur, bukan dugaan)

Diperiksa di `base/kernel_a37` @ `lineage-20`:

```
kernel/bpf/                    TIDAK ADA (nol berkas)
arch/arm64/net/                TIDAK ADA (nol JIT eBPF)
net/core/filter.c              888 baris        ← BPF klasik saja
   pembanding a6010 @22.2      3.493 baris      ← eBPF penuh
include/linux/utsname.h        tanpa spoof
init/Kconfig                   tanpa ANDROID_TREBLE_SPOOF_*
defconfig                      BPF_SYSCALL / CGROUP_BPF / PSI / OVERLAY_FS /
                               INCREMENTAL_FS / FS_VERITY / BINDERFS: tidak diset
```

Yang **sudah** ada dan penting:

```
CONFIG_COMPAT=y                       userspace 32-bit di kernel arm64  ✅
CONFIG_ANDROID_BINDER_IPC=y           + backport "modern binder with binder_alloc" (LOS 20)
CONFIG_SDCARD_FS=y  CONFIG_FUSE_FS=y  CONFIG_DM_VERITY=y  CONFIG_MEMCG=y
CONFIG_PSTORE{,_RAM}=y                ramoops sudah diperbaiki di lineage-20 (6fa5298755d)
memfd_create()                        mm/shmem.c:2678, terdaftar di arch/arm64/include/asm/unistd32.h:794 (__NR 385)
POLICYDB_VERSION_MAX = 30             security/selinux/include/security.h:44
```

`lineage-21` A37 = `lineage-20` + 2 commit (defconfig hung-task + perbaikan pstore).
Jadi basis yang diminta dan basis terkini praktis identik.

### 4.2 WAJIB — yang harus dikerjakan di kernel

Hanya **satu** item yang benar-benar wajib, dan ongkosnya kecil.

#### W-1. Spoof versi kernel lewat `utsname()` — 2 berkas

**Masalahnya nyata dan spesifik.** ART memutuskan boleh-tidaknya memakai `memfd_create()`
dari string `uname()`, bukan dari hasil syscall:

```c
// LineageOS/android_art@lineage-22.2 — libartbase/base/memfd.cc
static constexpr int kRequiredMajor = 3;
static constexpr int kRequiredMinor = 17;
struct utsname uts;
if (uname(&uts) != 0 || strcmp(uts.sysname, "Linux") != 0 ||
    sscanf(uts.release, "%d.%d", &major, &minor) != 2 ||
    (major < kRequiredMajor || (major == kRequiredMajor && minor < kRequiredMinor))) {
    errno = ENOSYS;
    return -1;
}
```

Kernel A37 **punya** `memfd_create` (ter-backport, terdaftar di tabel syscall arm64 native
maupun compat), tapi melaporkan `3.10` → gerbang `< 3.17` menutup, `memfd` dimatikan
padahal berfungsi. Di LOS 21 Anda lolos karena basis UL membawa
`art/0001-art-Conditionally-remove-version-check-for-memfd_create`. **ULH tidak
menyediakan fork `art` di 22.2**, jadi lubang itu terbuka lagi.

**Dua cara menutup, pilih salah satu:**

| | Cara | Ongkos | Jangkauan |
|---|---|---|---|
| **W-1a** *(disarankan)* | Port patch spoof acroreiser ke kernel A37 | 2 berkas: `include/linux/utsname.h` + `init/Kconfig` (±40 baris) | `init`, `zygote`, `system_server`, `perfetto`, `bpfloader`, `netbpfload` |
| W-1b | Bawa maju patch ART UL ke 22.2 | 3 berkas di `art/` | seluruh proses, tapi hanya ART |

Implementasi acroreiser (`ref/kernel_a6010`, `include/linux/utsname.h`, Kconfig
`init/Kconfig:1355–1385`) menyaring berdasarkan `current->comm` dan memberi **versi
berbeda untuk pemuat BPF**:

```c
if (!strcmp(current->comm, "bpfloader") || !strcmp(current->comm, "netbpfload"))
        strcpy(fake_release_prepended, CONFIG_ANDROID_TREBLE_SPOOF_BPF_KERNEL_VERSION_PREFIX);
else
        strcpy(fake_release_prepended, CONFIG_ANDROID_TREBLE_SPOOF_KERNEL_VERSION_PREFIX);
```

Commit yang memperkenalkannya berjudul **"utsname: spoof kernel version for netbpfload —
Fixes V boot"** (`f08945c89e8`). V = Android 15. Itu pernyataan langsung dari pemelihara
jangkar bahwa ini syarat boot A15.

⚠️ **Batas W-1a yang harus disadari:** penyaringan `current->comm` berarti proses aplikasi
hasil fork zygote (comm-nya = nama aplikasi) **tidak** ikut ter-spoof. Untuk ART itu
memadai — wilayah JIT yang penting disiapkan di `zygote`/`system_server` — tapi jangan
mengklaim cakupannya universal. Kalau nanti terbukti ada konsumen lain, W-1b menutup sisanya.

**Nilai yang dipakai**, dan ini bukan angka sembarangan:

```
CONFIG_ANDROID_TREBLE_SPOOF_KERNEL_VERSION_PREFIX     = "4.9.337"
CONFIG_ANDROID_TREBLE_SPOOF_BPF_KERNEL_VERSION_PREFIX = "4.19.325"
```

`4.19.325` dipilih karena `NetBpfLoad.cpp:1508` menuntut `REQUIRE(4, 19, 236)` — kalau
melaporkan seri 4.19 maka sub-versinya harus ≥ 236. Melaporkan `4.19.0` justru memicu
peringatan "Unsupported kernel version".

### 4.3 Keputusan besar: BPF — dua rute

Ini keputusan arsitektural terpenting di proyek ini, dan ongkos keduanya berbeda dua orde.

**Fakta yang membingkai keputusan:** di `lineage-22.2`, gerbang versi kernel di
`netbpfload` **bukan fatal** — saya membaca berkasnya utuh (1.695 baris):

```c
// bpf/loader/NetBpfLoad.cpp:1471
if (isAtLeastV && !isAtLeastKernelVersion(4, 19, 0)) {
    ALOGW("Android V requires kernel 4.19.");     // ← peringatan, BUKAN return 1
}
...
if (bad) { ALOGE("Unsupported kernel version (%07x).", kernelVersion()); }   // juga tidak return
```

Yang **fatal** justru hal lain, dan persis inilah yang menahan LOS 21 Anda:

```c
:1616   if (createSysFsBpfSubDir(location.prefix)) return 1;
:1624   if (createSysFsBpfSubDir("loader")) return 1;          ← bug yang Anda temukan di LOS 21
:1649   if (createSysFsBpfSubDir("netd_shared/mainline_done")) return 1;
```

Tanpa `CONFIG_BPF_SYSCALL`, `bpffs` tidak terdaftar, `/sys/fs/bpf` tidak ada, `mkdir`
gagal, `netbpfload` keluar sebelum menyetel `bpf.progs_loaded`, dan `netd` menggantung
selamanya di `BpfHandler.cpp` `waitForProgsLoaded()`.

#### Rute A — userspace BPF-less **(disarankan)**

Pakai set patch `MisterZtr/LineageOS_gsi@lineage-22.2`. Ini versi terawat dan hulu dari
tambalan yang Anda tulis tangan di LOS 21:

| repo | patch | isi |
|---|---|---|
| `packages/modules/Connectivity` | `0001` | `BpfHandler.cpp` — gagal attach program jadi `ALOGE`, bukan fatal |
| | `0002` | 7 berkas — dukung map BPF tak berfungsi (`BpfMap.h`, `NetBpfLoad.cpp`, `BpfNetMaps.java`, `NetworkStatsService.java`, …) |
| | `0003` | kembalikan indikator trafik untuk perangkat legacy |
| | `0006` | `NetBpfLoad.cpp` — abaikan lebih banyak galat BPF |
| | `0007` | revert `netdupdatable: add back abort() on init() fail` |
| | `0008` | cegah crash: `BpfNetMapsUtils`, `NetworkStatsService`, `BpfNetMaps` |
| `system/bpf` | `0001` | `legacyBpfLoader()` — `return` menggantikan `sleep(20); exit(121);` |
| `system/netd` | `0003`, `0004` | dukung no-bpf; jangan abort saat setup cgroup-bpf gagal |
| `packages/modules/DnsResolver` | `0001` | jangan abort kalau `DnsHelper` gagal init |
| `frameworks/native` | `0012` | matikan `gpuservice` di kernel lama tanpa BPF |

**Ongkos:** nol pekerjaan kernel. **Konsekuensi jujur:** statistik data per-aplikasi dan
firewall per-UID (Data Saver, pembatasan latar belakang) berjalan dengan akurasi berkurang
atau mati — patch `0003` mengembalikan sebagian indikator trafik lewat jalur lama.

#### Rute B — backport eBPF ke kernel

Ini yang acroreiser tempuh. **309 commit** dari `lineage-21` ke `lineage-22.2`, dan
klasifikasinya (dihitung dari subjek commit, `analysis/a6010_kernel_21to22_subjects.txt`):

| tema | commit | untuk LOS 22? |
|---|---|---|
| **bpf / eBPF** | **58** | inti Rute B |
| tracefs / ftrace / debugfs | 49 | opsional |
| uclamp / sched / cpufreq | 42 | opsional |
| spesifik a6010 / sisleyr | 40 | tidak berlaku |
| BFQ I/O scheduler | 23 | opsional |
| net / splice / af_unix | 19 | opsional |
| mm / kcompactd / oom | 16 | opsional |
| **utsname spoof** | **4** | **wajib (W-1)** |

⚠️ **Dan Rute B untuk A37 lebih mahal dari 58 commit itu.** Kernel a6010 adalah **arm
32-bit**; commit JIT-nya (`bpf, arm32: correct check_imm24`, `Kconfig: Fix ARM and BPF JIT`)
menyentuh `arch/arm/net/bpf_jit_32.c`. Kernel A37 **arm64** dan `arch/arm64/net/` **tidak
ada sama sekali** — JIT eBPF arm64 harus di-backport terpisah dari mainline 3.18+, pekerjaan
yang tidak punya preseden di jangkar mana pun yang saya periksa. Selain itu a6010 sudah
membawa kerangka eBPF sejak `lineage-20.0` (`kernel/bpf/{syscall,verifier,core,…}.c` sudah
ada di sana), sementara A37 mulai dari **nol**.

**Rekomendasi: Rute A.** Rute B disimpan sebagai peningkatan setelah ada homescreen, bukan
prasyarat boot.

### 4.4 OPSIONAL — layak, tapi hanya setelah boot

Semua diambil dari jangkar a6010 dan tidak satu pun memblokir boot:

| Item | Ongkos | Nilai untuk A37 |
|---|---|---|
| `uclamp` + `UCLAMP_TASK_GROUP` | 42 commit | Nyata di 2 GB RAM — Android 15 menyetel uclamp per-cgroup; tanpanya nilai itu diabaikan |
| BFQ v8r3 + `BLK_DEV_THROTTLING` | 23 commit | eMMC lambat; a6010 menjadikannya default (`CONFIG_DEFAULT_BFQ=y`) |
| `LZ4KD` (dari HUAWEI) untuk zram | 3 commit | 2 GB RAM — rasio kompresi lebih baik dari LZ4 |
| tracefs (`/sys/kernel/tracing`) | 49 commit | Perfetto/atrace lebih rapi. **Tidak wajib** — LOS 21 Anda mencapai `PHASE_THIRD_PARTY_APPS_CAN_START` tanpanya |
| `LLCON` (konsol kmsg ke layar) | 2 commit | **Alat diagnosis** — menampilkan panic/log di panel saat tidak ada USB. Mengingat riwayat "diam di logo tanpa entri USB", ini bernilai tinggi |
| kcompactd / kswapd backport | 16 commit | Mengurangi jank saat tekanan memori |

Perubahan defconfig a6010 21 → 22.2 juga menunjukkan satu hal menarik: mereka **kembali
dari `KERNEL_LZ4` ke `KERNEL_GZIP`** dan mematikan `RCU_FAST_NO_HZ`, `RCU_BOOST`,
`SLUB_CPU_PARTIAL`, `PROFILING`. Kalau A37 mengalami masalah boot yang tidak terjelaskan,
menyamakan kompresi kernel ke gzip adalah uji yang murah.

### 4.5 TERBUKTI TIDAK PERLU — jangan dikerjakan

Ini menghemat waktu paling banyak, jadi ditulis dengan buktinya:

| Dugaan umum | Vonis | Bukti |
|---|---|---|
| Backport SELinux policydb | **Tidak perlu** | LOS 22.2 mengompilasi versi **30** (`policy.go:31`, `Android.bp:47`); kernel A37 mendukung tepat **30** |
| `CONFIG_ANDROID_BINDERFS` | Tidak perlu | a6010 menjalankan LOS 22.2 tanpa mengaktifkannya |
| `INCREMENTAL_FS`, `FS_VERITY`, `OVERLAY_FS`, `PSI` | Tidak perlu | idem — tidak diset di defconfig a6010 22.2 |
| Naik ke kernel 4.19 sungguhan | Tidak perlu | Gerbang versi di `netbpfload` 22.2 hanya `ALOGW` (§4.3) |
| Kernel 64-bit / userspace 64-bit | Sudah aman | Yang fatal hanya `isKernel32Bit() && ≥5.16` (`:1477`) dan `≥6.7` (`:1483`). Kernel A37 **arm64** → tidak kena |
| `memfd_create` backport | **Sudah ada** | `mm/shmem.c:2678` |
| Modern binder | **Sudah ada** | commit `feda02b6ed5` di `lineage-20` |

---

## 5. Device tree

Basis: `rb_device_oppo_A37`. Branch `lineage-21` sudah jauh lebih maju dari `lineage-20`
(sudah lewat basis UL, APEX tak terkompres, HAL Bluetooth, ramoops, bootwatchdog).
**Buat `lineage-22` dari `lineage-21`, bukan dari `lineage-20`** — memulai dari 20 berarti
membuang temuan yang harganya sudah dibayar. Basis `lineage-20` tetap dipakai sebagai
rujukan seperti diminta, tapi bukan sebagai titik cabang.

### 5.1 Delta jangkar, dan apa yang tersisa setelah diperiksa ke pohon A37

Device tree a6010 `lineage-21.0` → `lineage-22.2`: **165 commit, 403 berkas**. Daftar di
bawah semula diturunkan dari diff itu. **Setelah pohon A37 ter-sync dan diperiksa langsung
(15 Agustus 2026), sebagian besar ternyata sudah beres atau tidak berlaku** — dicatat apa
adanya karena inilah bedanya membaca jangkar dan membaca perangkat sendiri:

| Item dari diff a6010 | Keadaan sebenarnya di `device/oppo/A37` |
|---|---|
| Tambah `android.hardware.bluetooth.audio@2.0` ke VINTF | **sudah ada** |
| Buang `vendor.lineage.touch` | **tidak pernah ada** — A37 tak punya touch HAL, jadi migrasi AIDL Rust a6010 tidak berlaku |
| ClearKey DRM ke AIDL | **sudah** — `android.hardware.drm-service.clearkey` (varian non-lazy) |
| Packaging HAL Bluetooth | **sudah** diperbaiki di `lineage-21`, terverifikasi di perangkat |
| Radio 1.1 → 1.4 | **sengaja tidak diikuti** — lihat §5.4 |
| `rro_overlays/PrivateSpaceOverlay` | **tidak dipakai, dan itu keputusan sadar** — lihat di bawah |

⚠️ **Koreksi terhadap versi pertama dokumen ini.** Di sana `PrivateSpaceOverlay` disebut
melindungi dari "perilaku yang tak didukung di RAM 2 GB". Itu **salah**. Isi aktifnya, di
luar blok komentar AOSP, hanyalah:

```xml
<user-types>
    <profile-type name="android.os.usertype.profile.PRIVATE" enabled='1'>
    </profile-type>
</user-types>
```

Overlay itu **menyalakan** Private Space, bukan meredamnya. Dan a6010 memasangnya hanya di
varian `lineage_a6010_gms_go_2gb.mk` / `lineage_sisleyr_gms_go_2gb.mk`, bukan di produk
dasarnya. Untuk A37 dengan RAM 2 GB, tidak memakainya adalah pilihan yang benar: Private
Space menambah profil pengguna kedua.

Yang belum diperiksa dan masih terbuka: **Wi-Fi Vendor HAL AIDL** (a6010 commit `8af9c3e8`)
dan **penyetelan ulang LMKD**. Keduanya Fase 6, bukan prasyarat boot.

### 5.2 HAL qcom-caf msm8916 — masalah struktural yang harus diputuskan

Diperiksa penuh dengan `ls-remote` di kedua org:

```
LineageOS/android_hardware_qcom_{audio,display,media}
    msm8916 berhenti di  lineage-19.0-caf-msm8916
    untuk 22.2 yang ada  msm8953, msm8996, msm8998, sdm660, sdm845, sm8150…  (bukan 8916)

LineageOS-UL/…          lineage-21.0-caf-msm8916      ← YANG DIPAKAI MANIFEST LOS 21 ANDA
                        tidak ada penerus 22.x
                        (kecuali display: ada lineage-22.2 generik, bukan caf-msm8916)

Ultra-Legacy-Hippeastrum/…   lineage-22.2-caf-msm8952   ← msm8952, bukan 8916
```

Jadi titik awal terdekat **bukan** 19.0 melainkan **`lineage-21.0-caf-msm8916` milik UL** —
kode yang sudah siap Android 14 **dan** sudah terbukti berbunyi di A37. Yang dibutuhkan
hanya lompatan satu versi, bukan tiga.

acroreiser menyelesaikannya dengan **memindahkan HAL ke dalam device tree**:

```makefile
# ref/device_a6010/BoardConfig.mk:232
USE_DEVICE_SPECIFIC_AUDIO   := true
USE_DEVICE_SPECIFIC_DISPLAY := true
USE_DEVICE_SPECIFIC_MEDIA   := true
DEVICE_SPECIFIC_AUDIO_PATH   := $(DEVICE_PATH)/hardware/audio
DEVICE_SPECIFIC_DISPLAY_PATH := $(DEVICE_PATH)/hardware/display
DEVICE_SPECIFIC_DISPLAY_PATH := $(DEVICE_PATH)/hardware/media   # ← lihat peringatan
```

Mekanisme ini **didukung resmi** di 22.2 — `vendor/lineage/build/core/qcom_target.mk:3-5`
membaca `USE_DEVICE_SPECIFIC_$(1)` + `DEVICE_SPECIFIC_$(1)_PATH`. Isinya 11 MB, dan
`hardware/audio/configs/` memang punya varian **`msm8916_32` dan `msm8916_64`**.

⚠️ **Cacat di jangkar yang jangan ikut disalin:** baris terakhir menyetel
`DEVICE_SPECIFIC_DISPLAY_PATH` untuk kedua kalinya. Akibatnya `DISPLAY_PATH` menunjuk ke
`hardware/media` dan `DEVICE_SPECIFIC_MEDIA_PATH` **tidak pernah disetel**. Yang benar:

```makefile
DEVICE_SPECIFIC_DISPLAY_PATH := $(DEVICE_PATH)/hardware/display
DEVICE_SPECIFIC_MEDIA_PATH   := $(DEVICE_PATH)/hardware/media
```

**Tiga pilihan untuk A37**, urut dari yang paling kecil risikonya:

- **5.2a** *(mulai dari sini)* — Bawa maju `LineageOS-UL/…@lineage-21.0-caf-msm8916` ke
  Android 15 di fork Anda sendiri. Ongkosnya sejenis dengan yang sudah Anda ukur di LOS 21
  (satu patch `String8::string()` → `c_str()` per repo), dan kodenya sudah berbunyi di A37.
- **5.2b** — Vendor ke device tree mengikuti a6010 (`hardware/{audio,display,media}`,
  11 MB, sudah punya `configs/msm8916_32` dan `msm8916_64`). Lebih rapi jangka panjang,
  tapi menukar basis audio/display yang **terbukti di A37** dengan yang belum.
- **5.2c** — Pakai `ULH@lineage-22.2-caf-msm8952` lalu turunkan ke 8916. Paling jauh dari
  perangkat; simpan sebagai cadangan terakhir.

Kalau 5.2a menemui galat kompilasi yang tidak sepadan, 5.2b adalah pindah yang wajar —
dan device tree a6010 di `ref/device_a6010/hardware/` sudah tersedia di mesin.

### 5.3 Kamera — `hal3on1`

Temuan yang mengubah rencana: di LOS 22.2, acroreiser **tidak** memakai jalur `device1/`
frameworks_av. `camera/hal3on1/Android.mk` membangun:

```makefile
LOCAL_MODULE       := camera.$(TARGET_BOARD_PLATFORM)   # → camera.msm8916
LOCAL_32_BIT_ONLY  := true
LOCAL_SRC_FILES    := HAL3on1-adapter.cpp               # 95 KB, satu berkas
```

Jadi adapter ini **menjadi** `camera.msm8916` (modul HAL3), dan blob HAL1 asli dikirim
sebagai `camera.legacy.msm8916`. CameraService melihat perangkat HAL3 — `device1/` tidak
dibutuhkan sama sekali. Properti pengendalinya ada di `device.mk`:

```
persist.camera.hal3on1.use_memfd=0
persist.camera.hal3on1.use_hwcomposer=1
persist.camera.hal3on1.use_sysfs_torch=1
```

Ini membatalkan rencana kamera LOS 21 (4 berkas ±98 KB di frameworks_av + ±200 baris
adaptasi). **Catatan penting:** `hal3on1` di a6010 disetel untuk sensor OV13850/OV5670.
A37 memakai sensor lain, jadi yang berpindah adalah **arsitekturnya**, bukan penyetelannya.
Kamera tetap Fase 6 — tidak dikerjakan sebelum ada homescreen.

### 5.4 Radio 1.4 — jangan ikut

a6010 pindah ke `android.hardware.radio@1.4` lewat wrapper in-tree
(`msm8916: radio: 1.4: legacy: Initial wrapper`). **A37 tidak boleh ikut di iterasi
pertama:** RIL adalah satu-satunya subsistem A37 yang sudah terbukti berfungsi penuh di
perangkat (LOS 20: telepon, SMS, LTE). Pertahankan `@1.1` sampai ada homescreen stabil.

### 5.5 Bluetooth — utang dari LOS 21

Di LOS 21 `android.hardware.bluetooth@1.0-service-qti` crash-loop tiap 5 detik:
`library "android.hardware.bluetooth@1.0.so" not found`. Penyebabnya **bukan** pencabutan
upstream — saya memeriksa `LineageOS/android_hardware_interfaces@lineage-22.2`:

```
200  bluetooth/1.0/default/Android.bp
200  camera/device/1.0/default/Android.bp
200  camera/provider/2.4/default/Android.bp
200  audio/7.1/config/Android.bp
```

Semua HAL legacy masih ada di 22.2. a6010 menambahkannya eksplisit ke `PRODUCT_PACKAGES`:

```makefile
android.hardware.bluetooth@1.0 \
android.hardware.bluetooth.audio@2.0-impl \
audio.bluetooth.default
```

Jadi perbaikannya soal *packaging*, bukan port.

---

## 6. Fase kerja

Urutannya mempertahankan pelajaran LOS 21: **diagnosis boot didahulukan, tidak ada fitur
dikerjakan sebelum ada homescreen.**

### Fase 0 — Mesin & basis bersih
- Pasang `repo`. Sediakan ≥16 GB RAM efektif (mesin ini 11 GB + 15 GB swap — akan jalan,
  akan lambat) dan ≥250 GB disk bebas untuk pohon + keluaran.
- `repo init -u https://github.com/LineageOS/android.git -b lineage-22.2`
- Pasang local manifest §3.2 → `repo sync`
- **Gerbang:** 0 HEAD kosong; `frameworks/native/libs/renderengine/gl/GLESRenderEngine.cpp`
  **ada**. Kalau tidak ada, fork ULH tidak terpasang dan seluruh rencana grafis batal.

### Fase 1 — Patch basis
- Terapkan set BPF-less `MisterZtr/LineageOS_gsi@lineage-22.2` (§4.3 Rute A).
- Bawa maju patch ART `memfd` **atau** kerjakan W-1a di kernel (§4.2).
- **Gerbang:** `system/bpf` dan `packages/modules/Connectivity` terpatch bersih; catat
  patch yang ditolak beserta alasannya sebelum lanjut.

### Fase 2 — Kernel
- W-1a: port spoof `utsname` (2 berkas) + `CONFIG_ANDROID_TREBLE_SPOOF_*` di
  `lineageos_a37f_defconfig`, nilai `4.9.337` / `4.19.325`.
- Pertimbangkan `LLCON` lebih awal — nilainya sebagai alat diagnosis melebihi ongkos 2 commit.
- **Gerbang:** kernel terkompilasi; `dt.img` **byte-identik** dengan LOS 20 yang boot
  (Anda sudah punya sha pembanding `459a2a6d…`). Setiap perubahan `dt.img` harus disengaja.

### Fase 3 — Device tree
- Cabang `lineage-22` dari `lineage-21`.
- VINTF: buang `vendor.lineage.touch` kalau pindah AIDL; tambah `bluetooth.audio@2.0`;
  **pertahankan radio @1.1**.
- Tambahkan `rro_overlays/PrivateSpaceOverlay`.
- Perbaiki packaging Bluetooth (§5.5). Pindahkan ClearKey DRM ke AIDL.
- Setel ulang LMKD mengikuti §5.1.
- **Gerbang:** `lunch` bersih; `checkvintf` lolos.

### Fase 4 — Build
- **Gerbang:** ROM jadi; `boot.img` ≤ 32 MB (LOS 21: 20,2 MB); bandingkan ukuran ramdisk
  dengan LOS 20 (1.352.145 B) dan LOS 21 (1.664.219 B).

### Fase 5 — Boot
- Pertahankan seluruh perkakas diagnosis LOS 21: `bootwatchdog.sh` (dengan pengecualian
  `odsign`, pagu 600 detik), ramoops lengkap di cmdline,
  `androidboot.init_fatal_reboot_target=recovery`.
- **Antisipasi yang sudah diketahui**: boot pertama akan menjalankan `odrefresh` penuh
  (LOS 21: 81,5 detik, 190× `dex2oat`). Jangan salah baca sebagai hang.
- **Tiga lapis penyebab LOS 21 harus diperiksa ulang di 22**: `ro.vndk.version`,
  `ro.hardware.egl=adreno`, dan jalur BPF. Lapis 1 dan 2 adalah setelan device tree yang
  ikut terbawa; lapis 3 kini ditangani set patch terawat.
- **Gerbang:** homescreen. Tidak ada pekerjaan Fase 6 sebelum ini tercapai.

### Fase 6 — Fungsi
Urut menurun berdasar risiko: Wi-Fi → RIL → Bluetooth → audio → kamera (`hal3on1`) →
sensor → GPS. Baru setelah itu pertimbangkan opsional §4.4.

---

## 7. Risiko dan yang belum terjawab

| | Risiko | Sikap |
|---|---|---|
| 1 | **ULH 22.2 tidak punya fork `frameworks/av`** — di 23.2 ada. Kalau ada yang dibutuhkan di sana untuk msm8916, harus dibawa sendiri | Set MisterZtr punya 24 patch `platform_frameworks_av`; periksa duluan sebelum menulis patch baru |
| 2 | Fork ULH `lineage-22.2` terakhir didorong **2026-05-18** — kemungkinan tertinggal ASB terhadap LineageOS resmi | Sama seperti UL beku di ASB 2025-03 di LOS 21. Terima; catat |
| 3 | HAL audio/display msm8916 tanpa penerus resmi di atas 19.0 | §5.2 — mulai 5.2a, 5.2b sebagai cadangan |
| 4 | Cakupan spoof `current->comm` tidak universal | §4.2, batasnya ditulis eksplisit; W-1b menutup sisanya |
| 5 | `hal3on1` belum pernah diuji di sensor A37 | Fase 6; arsitektur yang dipinjam, bukan penyetelan |
| 6 | RAM mesin build 11 GB | Batasi `-j`, andalkan swap 15 GB, atau pindah mesin |

**Yang belum saya buktikan dan tidak saya klaim:** bahwa A37 akan boot. Yang terbukti di
dokumen ini adalah setiap pemblokir yang *diketahui* punya jalan keluar yang dapat
ditunjuk ke kode, dan bahwa perangkat sekelas (msm8916, 3.10.108) benar-benar menjalankan
LOS 22.2 hari ini.

---

## 8. Lampiran — local manifest

Ada di `A37-22.xml` di direktori yang sama. Isinya §3.2 + tiga project A37
(device tree, kernel, vendor) + tiga HAL qcom-caf msm8916 sesuai pilihan §5.2a.
