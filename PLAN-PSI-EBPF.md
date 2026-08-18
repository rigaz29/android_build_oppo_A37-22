# Plan backport PSI dan eBPF — OPPO A37, kernel 3.10.108

Ditulis 18 Agustus 2026. Setiap klaim di sini diukur dari pohon kernel dan
perangkat, bukan dari ingatan umum tentang kedua fitur.

**Kesimpulan di muka:** keduanya TIDAK setara. PSI layak dikerjakan. eBPF untuk
kebutuhan Android **terhalang prasyarat yang jauh lebih besar dari eBPF itu
sendiri**, dan sebaiknya tidak dikerjakan.

---

## 1. Keadaan awal — yang diukur

```
kernel                     3.10.108
kernel/bpf/                TIDAK ADA
arch/arm64/net/bpf_jit*    TIDAK ADA
include/linux/bpf.h        TIDAK ADA
net/core/filter.c          24 KB  (classic BPF saja)

kernel/sched/psi.c         TIDAK ADA
include/linux/psi*.h       TIDAK ADA

cgroup v2 (unified)        TIDAK ADA — nol mount cgroup2 di perangkat,
                           tidak ada cgroup2_fs_type di kernel
```

---

## 2. PSI — LAYAK

### Kenapa layak

Semua titik hook yang PSI butuhkan **sudah ada** di 3.10:

| Berkas | Status | Dipakai PSI untuk |
|---|---|---|
| `kernel/sched/core.c` | ada, 23 titik enqueue/dequeue | `psi_task_change()` |
| `mm/vmscan.c` | ada | stall saat reclaim |
| `mm/page_alloc.c` | ada, 3 titik reclaim | stall saat alokasi |
| `mm/filemap.c` | ada, 11 titik page wait | stall I/O |
| `mm/compaction.c` | ada | stall saat kompaksi |
| `in_iowait` di scheduler | ada, 3 titik | pemisahan CPU vs IO |

PSI sistem-wide (`/proc/pressure/{cpu,memory,io}`) **tidak butuh cgroup v2**.
Cgroup-PSI butuh, tapi lmkd hanya memakai yang sistem-wide.

### Ruang lingkup

Berkas baru (dari 4.20, disederhanakan tanpa cgroup):
- `kernel/sched/psi.c`        (~1.300 baris hulu; tanpa cgroup ~900)
- `include/linux/psi.h`       (~50 baris)
- `include/linux/psi_types.h` (~180 baris)

Suntingan pada berkas yang sudah ada (~20 titik):
- `kernel/sched/core.c`   — `psi_task_change()` di enqueue/dequeue/ttwu
- `kernel/sched/sched.h`  — field `psi_flags` pada `struct task_struct`
- `kernel/sched/stats.h`  — pembungkus statistik
- `mm/vmscan.c`, `mm/page_alloc.c`, `mm/compaction.c` — `psi_memstall_enter/leave()`
- `mm/filemap.c`          — stall I/O
- `include/linux/sched.h` — anggota baru pada `task_struct`
- `kernel/sched/Makefile`, `init/Kconfig` — CONFIG_PSI

### Kesulitan yang HARUS diantisipasi

1. **`sched_clock()` antar-CPU belum tersinkron saat boot awal.** Sudah terbukti
   nyata di perangkat ini — lihat panic `sched_get_nr_running_avg` yang kita
   perbaiki. PSI sangat bergantung pada pengurangan cap waktu; setiap tempat
   yang menghitung selisih waktu harus dijepit agar tidak negatif, dengan
   pelajaran yang sama.

2. **`task_struct` di 3.10 tidak punya `psi_flags`.** Menambah anggota ke
   struct ini mengubah ABI kernel — semua modul harus dibangun ulang. Di
   perangkat ini seluruh kernel dibangun dari sumber, jadi aman, TAPI harus
   dipastikan tidak ada modul prebuilt (`.ko`) dari vendor.

3. **Perbedaan API scheduler.** 4.20 memakai `rq->curr`, `raw_spin_rq_lock()`,
   dan `sched_class` yang bentuknya berbeda dari 3.10. Hook tidak bisa disalin
   mentah; harus diadaptasi ke bentuk 3.10.

4. **`percpu` dan `seqcount` API** berubah antara 3.10 dan 4.20. PSI memakai
   `seqcount_t` per-CPU secara intensif.

### Langkah kerja

```
1. Ambil psi.c/psi.h/psi_types.h dari v4.20, buang seluruh jalur cgroup
2. Sesuaikan API: percpu, seqcount, sched_clock
3. Tambahkan CONFIG_PSI + CONFIG_PSI_DEFAULT_DISABLED di Kconfig
4. Pasang hook scheduler (paling berisiko — kerjakan terpisah, uji boot)
5. Pasang hook mm (lebih aman, efeknya terisolasi)
6. Jepit SEMUA selisih waktu agar tidak negatif
7. Uji: /proc/pressure/* muncul dan angkanya masuk akal saat diberi tekanan
8. Nyalakan ro.lmk.use_psi=true di device.mk, ukur ulang app-kill
```

### Ongkos dan hasil

- **Usaha:** sedang-berat. Realistis beberapa hari kerja dengan iterasi boot.
- **Risiko:** sedang. Hook scheduler bisa memicu panic; mitigasinya kerjakan
  bertahap dan simpan `console-ramoops` tiap percobaan.
- **Hasil:** lmkd memakai sinyal tekanan sungguhan, bukan ambang batas kasar.
  Pada perangkat 2 GB yang RAM bebasnya 90 MB, ini mengurangi app-kill yang
  terlalu dini maupun yang terlambat.

⚠️ **Catat kejujurannya:** tuning zram+swappiness yang baru kita kerjakan
memberi sebagian manfaat yang sama dengan risiko mendekati nol (terukur: swap
dari 0 MB jadi 163 MB terpakai, rasio 2,44:1). PSI menambah akurasi *keputusan*
lmkd, bukan menambah memori. Kerjakan PSI hanya kalau setelah tuning itu
app-kill masih terasa mengganggu.

---

## 3. eBPF — TIDAK DISARANKAN

### Yang sebenarnya Android 15 minta

Tipe program di `packages/modules/Connectivity/bpf/progs/`:

```
cgroupskb/egress|ingress      CGROUP_SKB           kernel 4.10+
cgroupsock/inet_create        CGROUP_SOCK          4.10+
cgroupsockrelease             INET_SOCK_RELEASE    5.10+
bind4/6, connect4/6, recvmsg4 CGROUP_SOCK_ADDR     4.17+
getsockopt/prog               CGROUP_SOCKOPT       5.3+
BPF_MAP_TYPE_RINGBUF                               5.8+
```

Dan `bpf/loader/NetBpfLoad.cpp:1461` menolak apa pun di bawah **kernel 4.9**.

Jadi cakupannya bukan "backport eBPF" melainkan membawa evolusi subsistem BPF
dari 4.1 sampai 5.10 — sekitar sepuluh tahun perkembangan kernel.

### Penghalang yang menentukan: cgroup v2 tidak ada

Ini yang membuatnya berbeda dari sekadar "mahal":

```
cgroup2_fs_type di kernel   : tidak ada
mount cgroup2 di perangkat  : 0
```

`BPF_PROG_TYPE_CGROUP_SKB` — inti akuntansi trafik Android — **menempel pada
hierarki cgroup v2**. cgroup v2 masuk kernel 4.5 sebagai penulisan ulang inti
subsistem cgroup, bukan tambahan.

Konsekuensinya berlapis:
1. Backport eBPF saja tidak cukup; harus backport cgroup v2 juga.
2. Seluruh penyiapan cgroup Android di perangkat ini (`libprocessgroup`,
   `task_profiles.json`, `cgroups.json`) dibangun di atas v1. Menambah v2
   berarti mengubah keduanya bersamaan.
3. Kita SUDAH menabrak konsekuensi cgroup v1 di sesi ini —
   `createProcessGroup failed` untuk `vendor.audio-hal` — dan itu di jalur yang
   jauh lebih sederhana.

### Kalau tetap ingin sebagian

Ada dua program yang **tidak** butuh cgroup v2:

| Program | Menempel ke | Yang dipulihkan |
|---|---|---|
| `schedcls` (clatd) | qdisc/tc | 464XLAT — hanya berguna di jaringan IPv6-only |
| `schedcls` (offload) | qdisc/tc | tethering offload — optimasi kecepatan |

Keduanya tetap menuntut inti eBPF (syscall, verifier, map, JIT arm64) dan
kernel melaporkan ≥ 4.9. Ongkos hampir sama dengan backport penuh, hasilnya dua
fitur pinggiran.

**Yang paling diinginkan orang — statistik pemakaian data per aplikasi —
justru yang terkunci di balik cgroup v2.**

### Kesimpulan

Tidak disarankan. Bukan karena mahal, tapi karena prasyaratnya (cgroup v2)
lebih besar daripada fitur yang diminta, dan menyentuh bagian kernel yang
paling berisiko sekaligus paling terikat dengan userspace Android.

---

## 4. Rekomendasi berurut

| Urutan | Pekerjaan | Usaha | Risiko | Hasil |
|---|---|---|---|---|
| 1 | zram + swappiness + scheduler | **selesai** | rendah | terukur: swap 0 → 163 MB |
| 2 | Ukur ulang app-kill setelah (1) | jam | nol | menentukan apakah (3) perlu |
| 3 | PSI tanpa cgroup | beberapa hari | sedang | lmkd lebih akurat |
| — | eBPF | minggu-bulan | tinggi | terhalang cgroup v2 |

Langkah 2 penting: kerjakan PSI hanya kalau datanya menunjukkan masih perlu.

---

## 5. Cara memverifikasi PSI kalau dikerjakan

Bukan "terasa lebih lancar", melainkan angka:

```
# 1. Antarmukanya ada dan hidup
cat /proc/pressure/memory      # some/full avg10 avg60 avg300 total

# 2. Angkanya bergerak saat diberi tekanan
#    (buka banyak aplikasi, lalu baca ulang — avg10 harus naik)

# 3. lmkd benar-benar memakainya
getprop ro.lmk.use_psi         # true
logcat -b all | grep -i "lmkd.*psi"

# 4. Pembanding app-kill, dengan cara yang sama seperti sesi ini:
#    buka 5 aplikasi, hitung yang bertahan, dan hitung pembunuhan lmkd
```

Angka pembanding dari sesi ini, setelah tuning zram: dari 5 aplikasi yang
dibuka pada RAM bebas 15 MB, **3 bertahan dan lmkd membunuh 0**.
