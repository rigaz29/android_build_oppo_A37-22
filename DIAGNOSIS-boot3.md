# Boot 3 — system_server abort di JNI ClatCoordinator, tertahan 370 detik

Artefak: `report/bootfail3/`. ROM `...082617...` (penjaga netd eBPF + bootwatchdog 300).

## Yang sudah beres

Kedua perbaikan boot 2 **bekerja**, dan itu terbaca langsung di properti:

```
init.svc.netd     running     <- boot 2: restarting
init.svc.zygote   running     <- boot 2: restarting
tertahan          370 detik   <- boot 2: 199
```

Boot juga melaju jauh lebih dalam. Servis terakhir yang tercatat start:

```
bootanim      90,9 s
cppreopts     94,2 s
artd         111,2 s
```

## Akar baru: `abort()` di dalam `JNI_OnLoad`

12 tombstone `system_server`, backtrace identik semuanya:

```
#00 libc.so (abort+138)
#01 libservice-connectivity.so (register_com_android_server_connectivity_ClatCoordinator+450)
#02 libservice-connectivity.so (JNI_OnLoad+106)
#03 libart.so (JavaVMExt::LoadNativeLibrary+2400)
```

Didahului pesan verifikasi yang menyebutkan persis apa yang kurang:

```
'/sys/fs/bpf' mode is 00 != 041777
'/sys/fs/bpf/net_shared' mode is 00 != 041777
'/sys/fs/bpf/net_shared/map_clatd_clat_egress4_map' mode is 00 != 0100660
bpf_obj_get '/sys/fs/bpf/net_shared/map_clatd_clat_egress4_map' failed, errno=38
```

`mode is 00` berarti `lstat` gagal — berkasnya **tidak ada sama sekali**. Dan
**errno 38 = ENOSYS**: syscall `bpf()` sendiri tidak ada, konsisten dengan
`CONFIG_BPF_SYSCALL` yang memang tidak ada di kernel ini.

Sumbernya `com_android_server_connectivity_ClatCoordinator.cpp`. Makro `ALOGF`
menyalakan `fatal` pada tiap ketidakcocokan, dan fungsinya ditutup dengan:

```cpp
if (fatal) abort();
```

Karena ini terjadi di `JNI_OnLoad`, `system_server` mati **sebelum satu servis
pun dimulai** — jauh lebih awal daripada kegagalan servis biasa.

## Perbaikan

Penjaga dipasang di `verifyClatPerms()`, **setelah** pemeriksaan direktori dan
biner clatd tapi **sebelum** bagian BPF:

```cpp
if (android::base::GetProperty("ro.kernel.ebpf.supported", "") == "false") {
    ALOGI("eBPF tidak didukung perangkat ini, verifikasi BPF clat dilewati.");
    return;
}
```

UL menyelesaikannya dengan mencabut `if (fatal) abort();` sepenuhnya. Cara di
sini lebih sempit dan sengaja: dua pemeriksaan pertama — direktori dan biner
clatd, yang menurut komentar hulu sendiri *"99% likely to be build problems"* —
tetap berlaku penuh, dan `abort()` tetap menjadi jaring pengaman sungguhan di
perangkat yang memang punya eBPF.

## Sapuan, supaya ini tidak jadi siklus keempat

Ini abort BPF-less **ketiga** yang ditemukan satu per satu lewat flash fisik
(netd, lalu clat). Karena itu seluruh jalur native disapu sekaligus:

| Diperiksa | Hasil |
|---|---|
| `abort()` lain di `bpf/netd/BpfHandler.cpp:153-168` | tak terjangkau — semuanya di dalam `BpfHandler::init()` yang sudah dilewati penjaga netd |
| pendaftaran JNI lain di `service/jni/onload.cpp` | `TestNetworkService`, `ServiceManagerWrapper`, `TimerFdUtils` — **nol** `abort()` |
| `DnsBpfHelper` | mengembalikan `base::Error(EUNATCH)`, bukan abort |
| `BpfNetMaps` (Java) | konstruktornya sudah berpagar `try/catch` dari trebledroid, 20 penjaga null |

Jadi `libservice-connectivity` kini bersih: satu-satunya `abort()` di seluruh
pendaftaran JNI-nya adalah yang barusan dijaga.

## Yang diawasi, belum diperbaiki

**`composer@2.1-service`** crash 1× lagi dengan pola yang sama seperti boot 2 —
`RefBase: object ... with strong count 1 deleted. Double owned?` di
`IdleInvalidator::~IdleInvalidator` (`libqdutils`), dipanggil dari
`qhwc::MDPComp::init`.

Sumbernya terlihat: `IdleInvalidator : public android::Thread` (turunan RefBase)
dipegang `static android::sp<IdleInvalidator> sInstance`, sementara
`getInstance()` mengembalikan pointer mentah. Pesan RefBase itu muncul ketika
objek dihancurkan padahal `sp<>` masih memegangnya.

**Tidak diperbaiki sekarang** karena tidak menghalangi: `init.svc.vendor.hwcomposer-2-1`,
`init.svc.surfaceflinger`, dan `init.svc.bootanim` ketiganya `running` saat log
diambil — servisnya crash sekali di awal lalu pulih. Kalau setelah system_server
sehat ia berubah jadi crash-loop, di sinilah titik masuknya.

## Catatan instrumen

`Log$TerribleFailure: Outgoing transactions from this process must be FLAG_ONEWAY`
di `SystemServer.createSystemContext` tampak seperti kegagalan fatal — lengkap
dengan blok `E AndroidRuntime` dan stack trace penuh. Ia **bukan** penyebabnya:
baris berikutnya menunjukkan `system_server` melanjutkan ke
`InitBeforeStartServices took 205ms`, `StartServices`, `startBootstrapServices`.
Sebuah WTF yang dicatat lengkap tidak sama dengan proses yang mati.
