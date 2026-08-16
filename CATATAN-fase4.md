# Fase 4 — catatan kegagalan build

Diperbarui 16 Agustus 2026. Setiap baris diikat ke pesan galat sungguhan, bukan ingatan.

Percobaan 1–14. Tujuannya bukan mendaftar kegagalan melainkan **mengelompokkannya per
akar**, karena akar yang sama muncul berkali-kali dan sekali diketahui bisa dihabisi
sekaligus.

---

## Empat akar

### A. Fork ULH `frameworks/base` tertinggal 295 commit — **dihabisi**

| % | Galat |
|---|---|
| 11 | `frameworks/opt/telephony` butuh `R.integer.auto_data_switch_availability_switchback_*` yang tidak ada di fork |
| 11 | `ServiceState.setOutOfService` 2 argumen vs 1 di pemanggil resmi (7 titik) |
| 12 | `IUserSwitchObserver.onBeforeUserSwitching(int)` vs `(int, IRemoteCallback)`, plus `oneway` yang dicabut hulu dari 4 metode |

Terukur: fork tertinggal **295 commit** (302 berkas, 8420+/1997−) sambil hanya membawa
7 commit sendiri. Dua di antaranya (revert telephony) berpasangan dengan fork
`frameworks_opt_telephony` yang ULH **tidak sediakan** di 22.2 — basisnya tidak konsisten
dengan dirinya sendiri.

**Penyelesaian:** `frameworks/base` pindah ke **LineageOS resmi** + lima patch UL dari kit
LOS 21 (`0004`, `0005`, `0006`, `0008`, `0009`). Itu justru mengembalikan struktur yang
sudah terbukti build dan boot di LOS 21. `frameworks/native` **tetap** fork ULH — di
sanalah RenderEngine GLES berada.

### B. Legacy ↔ resmi tidak sepadan (sepolicy) — **dihabisi**

Empat lapis berturut-turut, masing-masing baru terlihat setelah yang di atasnya beres:

1. `attribute vendor_hal_soter_client is not declared` — `device/lineage/sepolicy/qcom`
   resmi mengasumsikan `device/qcom/sepolicy` **modern**; A37 memakai varian legacy.
2. `Duplicate declaration of type` — **kesalahan saya.** Saya juga mendeklarasikan
   `vendor_hal_gnss_qti` dan `vendor_hal_perf_default` setelah memeriksa dengan pola
   literal `attribute vendor_hal_X;`. Yang terlewat: keduanya sudah ada lewat jalur lain,
   yaitu `type hal_X, domain;` yang lalu di-rename substitusi M4.
3. `unknown type vendor_hal_gnss_qti_exec` — substitusi M4 mengganti token `hal_gnss_qti`
   tapi **tidak** `hal_gnss_qti_exec`; token berbeda. Menambal tipe satu per satu adalah
   jalan yang salah; yang benar tidak menerapkan substitusinya sama sekali untuk platform
   ini, persis yang LineageOS-UL lakukan.
4. `attribute hal_lineage_camera_motor_client is not declared` — konsekuensi dari
   pemulihan di (3): patch "Revert Remove legacy camera HAL1 sepolicy" ikut membawa baris
   warisan LOS 21 yang merujuk HAL kamera bermotor, yang sudah dicabut di 22.2.

**Pelajaran:** memulihkan dukungan legacy era LOS 21 ke basis 22.2 berarti ikut membawa
rujukan ke hal-hal yang sudah dicabut hulu. Tiap pemulihan harus diperiksa isinya.

Dan: di sepolicy, "tidak ada deklarasi atribut" ≠ "tidak ada deklarasi". Substitusi M4
membuat nama di berkas sumber berbeda dari nama di policy akhir.

### C. Kode lama yang baru ditolak toolchain A15

| Tempat | Galat |
|---|---|
| device tree `gps/` | 3 bug format string. `loc_eng.cpp:2690` punya tiga `%u` dengan dua argumen — `%u` ketiga membaca sampah dari stack. Bug ini **sudah ikut terkirim di ROM LOS 20** yang dipakai sehari-hari |
| device tree `libshims/` | konstruktor `SensorEventQueue` dapat dua parameter baru di A15 |
| `hardware/qcom-caf/wlan` | `-DWCNSS_QMI` dan `-DWCNSS_QMI_OSS` aktif bersamaan → `wcnss_init_qmi` dideklarasikan dua kali dengan jenis berbeda |
| HAL CAF msm8916 `audio` | `using namespace std;` tanpa header std, **8 berkas** |
| HAL CAF msm8916 `display` | `String8::string()` privat → `c_str()` |
| `device.mk` A37 | nama kunci `PRODUCT_BUILD_PROP_OVERRIDES` berubah di A15 dan kini divalidasi ketat |

### D. Kelalaian prosedural saya

| | |
|---|---|
| `repo init` tanpa `--git-lfs` | Prebuilt WebView turun sebagai pointer 133 byte. Gagal di 38% dengan pesan yang tidak menyebut LFS sama sekali. **Flag ini sudah tertulis di `PLAN-LOS22.md` sejak awal.** |
| Patch `String8` tidak diterapkan di muka | Sudah ada di kit LOS 21, dan `PLAN.md` LOS 21 menyebutnya satu dari **tiga hal yang tetap wajib**. Saya membacanya di awal sesi lalu menunggu build menabraknya. Patch `display` **dan** `audio` keduanya terap bersih. |
| Manifest membuang 22 `<linkfile>` | `remove-project` + tambah-ulang menghapus anak `<linkfile>` → 443 galat "module already defined" |

---

## Perubahan cara kerja yang paling membayar

Sepuluh percobaan pertama masing-masing menemukan **satu** galat, dengan ongkos ~90 menit
sampai titik gagalnya. Empat di antaranya ada di kode yang bisa dikompilasi terpisah dalam
hitungan menit.

Sejak percobaan 10 urutannya dibalik:

```bash
tools/run-devmods.sh   # 17 modul device tree      -> ~5 menit
tools/run-shims.sh     # 3 modul shim
tools/run-cafhal.sh    # SELURUH modul 3 HAL CAF, dengan -k
```

`-k` membuat ninja lanjut setelah galat pertama, sehingga **semua** galat terkumpul dalam
satu putaran. Sapuan pertama langsung memunculkan dua kelas sekaligus (String8 + memcpy)
yang jika lewat build penuh akan makan dua siklus terpisah.

Prinsip yang sama berlaku untuk sapuan kode: saat satu bug format string ditemukan,
seluruh device tree disapu dan **dua bug lagi** ketahuan sebelum sempat menggagalkan build.

---

## Yang sengaja dibiarkan gagal

`msm-vidc-test` — `'utils/Log.h' file not found`. Alat uji, tidak diminta `device.mk` mana
pun, jadi tidak ikut ROM. Memperbaikinya menuntut perubahan sistem build untuk alat yang
tidak dipakai.

---

## Hasil akhir — Fase 4 SELESAI

**Percobaan 18, 16 Agustus 2026 07:17 — rc=0, nol target gagal.**

```
lineage-22.2-20260816_071019-UNOFFICIAL-A37.zip   754.028.285 B
boot.img          20.246.528 B  (19,3 MiB dari partisi 32 MiB)
recovery.img      30.945.280 B
system.img     1.700.319.764 B
```

### Gerbang yang diperiksa, bukan diasumsikan

Identitas dan spoof — port kunci A15 (`BuildDesc`/`DeviceName`) bekerja persis
seperti yang dituju:

```
ro.build.version.release    15
ro.lineage.version          22.2-20260816_071012-UNOFFICIAL-A37
ro.product.system.device    A37     <- identitas Lineage utuh
ro.lineage.device           A37     <- pencocokan OTA aman
ro.build.product            A37f    <- spoof stok
ro.build.description        msm8916_64-user 5.1.1 LMY47V eng.root...
```

adb, dari rantai yang diprediksi `post_process_props.py:35-42`:

```
ro.adb.secure               0
persist.sys.usb.config      adb
```

Perbaikan boot LOS 21 terbawa utuh:

```
ro.hardware.egl             adreno        <- Lapis 2 LOS 21
ro.vndk.version             tidak diset   <- Lapis 1 LOS 21
```

Kernel W-1 terverifikasi di artefak yang DIKIRIM, bukan hanya di hasil
kompilasi antara:

```
kernel di boot.img   18.310.776 B  = identik dengan Image hasil build W-1
string '3.17'        7x
string 'netbpfload'  1x
```

### Empat kegagalan terakhir: asumsi yang diam-diam terbalik di A15

Setelah sepolicy beres, sisanya bukan lagi soal legacy vs modern melainkan
**default yang berubah diam-diam**:

| Kegagalan | Yang berubah |
|---|---|
| `Key "PRIVATE_BUILD_DESC" isn't a valid prop override` | `PRODUCT_BUILD_PROP_OVERRIDES` kini divalidasi; kunci lama tidak sah. Padanannya `BuildDesc`/`DeviceName` |
| `checkvintf INCOMPATIBLE` | `vendor.lineage.health` naik ke AIDL V2; matrix device masih menyebut V1 dan tanpa `IFastCharge` |
| `META/ab_partitions.txt is required for ab_update` | `board_config.mk:945` — `AB_OTA_UPDATER` kosong dulu berarti non-A/B, di A15 berarti **A/B** |
| `zip I/O error: Bad address` | `non_ab_ota.py` memanggil zip tanpa `-y`; terpicu karena target berupa direktori DAN build berjalan sebagai root |

### Dua kelalaian yang harus dicatat

`PLAN.md` LOS 21 menyebut **tiga** hal yang tetap wajib meski basis berganti.
Dua di antaranya saya biarkan sampai build menabraknya, masing-masing menelan
satu siklus penuh (~1 jam):

- `String8::string()` di qcom-caf — patchnya sudah ada di kit LOS 21 dan terap
  bersih untuk `display` **dan** `audio`
- `zip -y` di `non_ab_ota.py` — patchnya juga sudah ada, terap bersih, dan
  commit-nya bahkan sudah menjelaskan syarat pemicunya

Yang ketiga, Camera HAL1 `device1/`, tidak berlaku di LOS 22 karena jalurnya
berpindah ke `hal3on1`.

Pelajarannya bukan "baca rencana lebih teliti" melainkan: **daftar
prasyarat yang sudah terbukti dari versi sebelumnya diterapkan DI MUKA, bukan
menunggu gerbang menemukannya.**
