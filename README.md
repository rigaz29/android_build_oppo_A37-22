# android_build_oppo_A37-22

Rencana porting **LineageOS 22.2 (Android 15, SDK 35)** untuk **OPPO A37 / A37f / A37fw** —
Qualcomm MSM8916 (Snapdragon 410), kernel 3.10.108 arm64, userspace 32-bit, 2 GB RAM,
Adreno 306.

Pendahulunya: [`android_build_oppo_A37-21`](https://github.com/rigaz29/android_build_oppo_A37-21)
(LineageOS 21 — pernah boot sampai setup wizard di basis UL) dan
[`android_build_oppo_A37-20`](https://github.com/rigaz29/android_build_oppo_A37-20)
(LineageOS 20 — **ROM terpasang dan dipakai di perangkat**: boot, Wi-Fi, Bluetooth, RIL).

---

## Isi

| Berkas | Keterangan |
|---|---|
| **[`PLAN-LOS22.md`](PLAN-LOS22.md)** | Dokumen utama. Peta basis, analisis kernel wajib/opsional, device tree, 7 fase kerja |
| [`A37-22.xml`](A37-22.xml) | Local manifest. 9 `remove-project`, 17 project — sudah divalidasi parser XML |
| [`analysis/`](analysis/) | Keluaran mentah yang dikutip `PLAN-LOS22.md`: 309 subjek commit kernel a6010 `lineage-21` → `lineage-22.2`, dan delta defconfig-nya |

---

## Tiga hal yang berubah dari LOS 21

**1. Basisnya bukan LineageOS-UL lagi.** Org itu berhenti di `lineage-21.0`. Penerus untuk
22/23 adalah [`Ultra-Legacy-Hippeastrum`](https://github.com/Ultra-Legacy-Hippeastrum),
dan modelnya berbeda: bukan manifest pengganti, melainkan **fork per-repo** branch
`lineage-22.2` yang dipasang lewat local manifest di atas LineageOS resmi.

```
repo init -u https://github.com/LineageOS/android.git -b lineage-22.2
```

**2. Dua pemblokir terbesar LOS 21 sudah tidak ada.**

```
ULH/android_frameworks_native@lineage-22.2   libs/renderengine/gl/GLESRenderEngine.cpp  200
LineageOS/…@lineage-22.2                     libs/renderengine/gl/GLESRenderEngine.cpp  404
```

RenderEngine GLES sudah menyatu di basis — 14.464 baris patch tidak perlu diulang. Dan
kamera tidak lagi lewat restorasi `device1/` di `frameworks/av`, melainkan **`hal3on1`**
yang membangun ulang `camera.$(TARGET_BOARD_PLATFORM)` sebagai modul HAL3 di dalam device
tree.

**3. Patch legacy datang dari tempat lain.** `ULH/legacy_support_patches` hanya punya
branch `lineage-23.2`, dan README-nya menuntut branch patch = branch target. Untuk 22.2
sumbernya [`MisterZtr/LineageOS_gsi@lineage-22.2`](https://github.com/MisterZtr/LineageOS_gsi/tree/lineage-22.2/patches/trebledroid)
— 193 patch di 25 repo, termasuk seluruh jalur BPF-less.

---

## Kernel: satu baris wajib, sisanya opsional

| | Item |
|---|---|
| **Wajib** | Spoof versi kernel lewat `utsname()` — 2 berkas, ±40 baris. ART 22.2 memutuskan boleh-tidaknya `memfd_create` dari string `uname()` dengan ambang ≥ 3.17; kernel A37 **punya** syscall-nya (`mm/shmem.c:2678`) tapi melapor `3.10`. Di LOS 21 lubang ini ditutup basis UL — ULH **tidak** menyediakan fork `art` di 22.2 |
| **Opsional** | uclamp (42 commit), BFQ v8r3 (23), LZ4KD, LLCON, tracefs (49). Tidak satu pun memblokir boot |
| **Tidak perlu** | Backport SELinux — LOS 22.2 mengompilasi policydb **30** (`system/sepolicy/build/soong/policy.go:31`), kernel A37 mendukung tepat **30**. Juga: binderfs, incfs, fs-verity, dan naik ke 4.19 sungguhan |

Keputusan terbesarnya **eBPF**. A37 nol infrastruktur BPF — `net/core/filter.c` 888 baris
lawan 3.493 di jangkar a6010. Rencana ini memilih **rute userspace**: backport ala
acroreiser butuh 58 commit dan lebih mahal lagi untuk A37, karena kernel a6010 arm32
sedangkan A37 arm64 dengan `arch/arm64/net/` yang tidak ada sama sekali. Alasan lengkap di
[`PLAN-LOS22.md`](PLAN-LOS22.md) §4.3.

---

## Yang jadi pekerjaan sungguhan

HAL qcom-caf **msm8916**. Tidak ada penerus 22.x di org mana pun:

```
LineageOS      berhenti di  lineage-19.0-caf-msm8916
LineageOS-UL   berhenti di  lineage-21.0-caf-msm8916   <- dipakai manifest LOS 21 kita
ULH            hanya        lineage-22.2-caf-msm8952   <- msm8952, bukan 8916
```

Titik awalnya kode UL 21.0 — sudah siap Android 14 **dan** sudah terbukti berbunyi di A37.
Satu lompatan versi, bukan tiga. Cadangannya: mem-*vendor* HAL ke dalam device tree seperti
a6010 (`USE_DEVICE_SPECIFIC_*`, didukung resmi di `vendor/lineage/build/core/qcom_target.mk`).

---

## Jangkar bukti

[`acroreiser/android_kernel_lenovo_a6010`](https://github.com/acroreiser/android_kernel_lenovo_a6010)
dan device tree-nya — **msm8916, kernel 3.10.108, punya branch sampai `lineage-23.2`**.
Perangkat berbeda, chipset dan versi kernel sama. Seluruh angka di `analysis/` berasal dari
sana.

⚠️ Batasnya: a6010 punya panel, kamera, dan blob berbeda dari A37, dan kernelnya **arm 32-bit**
sedangkan A37 **arm64**. Jangkar ini menjawab pertanyaan level chipset dan level Android 15
— bukan level A37.

---

## Metodologi

Setiap klaim yang menentukan keputusan diikat ke berkas dan baris yang bisa diperiksa ulang.
Yang belum terbukti ditulis sebagai belum terbukti — termasuk yang paling penting: **dokumen
ini tidak mengklaim A37 akan boot.** Yang ditunjukkan adalah bahwa setiap pemblokir yang
diketahui punya jalan keluar yang dapat ditunjuk ke kode, dan bahwa perangkat sekelas
menjalankan LOS 22.2 hari ini.

---

## Status pengerjaan

Diperbarui 15 Agustus 2026. Setiap gerbang di bawah dijalankan sungguhan, bukan diperkirakan.

| Fase | Status | Gerbang |
|---|---|---|
| **0** Basis bersih | ✅ | `repo sync` rc=0, 23m41s, 162 GB, **1149 project, nol HEAD kosong**. `frameworks/native/libs/renderengine/gl/GLESRenderEngine.cpp` **ada** (1866 baris) |
| **1** Patch BPF-less | ✅ | 13 patch (11 trebledroid + 2 sendiri), `apply-fase1.sh` idempoten, gerbang jalur keluar dini lolos |
| **2** Kernel W-1 | ✅ | Kernel terkompilasi dengan `aarch64-linux-android-4.9`, `Image` 18.310.776 B, dan literal spoof terbukti ada di `kernel/sys.o` (tempat `uname()` dilayani) |
| **3** Device tree & konfigurasi | ✅ | `lunch lineage_A37-bp1a-userdebug` + `m nothing` → **rc=0, nol galat, 20m58s**, `build.lineage_A37.ninja` 1,04 GB tergenerate |
| **4** Build ROM | berjalan | 14 percobaan sejauh ini; lihat `CATATAN-fase4.md` |
| **5** Boot | belum | |
| **6** Fungsi | belum | |

Perintah gerbang Fase 3:

```bash
source build/envsetup.sh
lunch lineage_A37-bp1a-userdebug     # format TIGA bagian, release bp1a
m nothing                            # ~21 menit di mesin 12 core / 11 GB
```
