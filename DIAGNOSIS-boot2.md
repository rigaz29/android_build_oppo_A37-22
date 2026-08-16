# Boot 2 — netd crash-loop, tertahan 199 detik

Artefak: `report/bootfail2/`. ROM `...075116...` (perbaikan renameat2).

## Yang sudah beres

Akar boot 1 **tuntas**. `/data/system/environ/classpath` kini terbentuk, 4439 B,
`BOOTCLASSPATH` terisi penuh. Perangkat bertahan 199 detik, naik dari 120.

## Akar baru: `netd` abort di `BpfHandler::init`

24 tombstone `/system/bin/netd`, `init.svc.netd = restarting` saat log diambil,
`sys.boot_completed` tidak pernah ada. Backtrace:

```
#01 libnetd_updatable.so (android::net::BpfHandler::init(char const*)+2618)
#02 libnetd_updatable_init.cfi
#03 /system/bin/netd (main.cfi+218)
```

`BpfHandler.cpp:226-229`:

```cpp
if (!base::SetProperty("ctl.start", "mdnsd_netbpfload")) {
    ALOGE("Failed to set property ctl.start=mdnsd_netbpfload, see dmesg for reason.");
    abort();
}
```

Terekam di logcat persis berurutan:

```
I NetdUpdatable: libnetd_updatable_init: Initializing
W libc     : Unable to set property "ctl.start" to "mdnsd_netbpfload": PROP_ERROR_HANDLE_CONTROL_MESSAGE (0x20)
E NetdUpdatable: Failed to set property ctl.start=mdnsd_netbpfload, see dmesg for reason.
```

Dan jebakan kedua menunggu di belakangnya seandainya `ctl.start` berhasil:
`waitForNetProgsLoaded()` adalah loop **tak terhingga** menanti
`/sys/fs/bpf/netd_shared/mainline_done`, berkas yang tidak akan pernah muncul di
kernel tanpa `CONFIG_BPF_SYSCALL`.

Perangkat sudah menyatakan dirinya dengan benar — `ro.kernel.ebpf.supported=false` —
tapi tidak ada satu pun kode di pohon 22 yang membaca properti itu.

## Perbaikan

Penjaga di `bpf/netd/NetdUpdatable.cpp`: kalau `ro.kernel.ebpf.supported=false`,
lewati `sBpfHandler.init()` dan kembalikan 0.

Kondisinya sengaja **tidak** menyalin hulu UL, yang keliru:
`__system_property_get` mengembalikan **panjang** nilai, bukan status, sehingga
`!= 0` justru benar saat propertinya bernilai `"false"` — kebalikan dari maksudnya.
LOS 21 sudah menemukan dan mengoreksi ini.

Tiga hal yang diperiksa agar melewati init tidak menimbulkan kerusakan baru:

| Diperiksa | Hasil |
|---|---|
| `tagSocket` / `untagSocket` dengan handler tak terinisialisasi | aman — keduanya dibuka `if (!mCookieTagMap.isValid()) return -EPERM;`, dan komentar `BpfHandler.cpp:290` menyatakan peta itu sengaja diinisialisasi terakhir sebagai penanda validitas induk |
| `netd main.cpp:146-149` menoleransi kegagalan | ya, `//exit(1);` sudah dikomentari — tapi `abort()` melompati pagar itu |
| jalur netd setelah titik abort | `Controllers.cpp` tidak menyentuh BPF; `makeNFLogListener` butuh NFLOG, dan `CONFIG_NETFILTER_NETLINK_LOG=y` ada di `.config` hasil build (terpilih otomatis lewat `NETFILTER_XT_TARGET_NFLOG`) |

## Yang TIDAK jadi penghalang, meski tampak begitu

**`composer@2.1-service`** — 2 tombstone, `RefBase: object ... with strong count 1
deleted. Double owned?` di `IdleInvalidator::~IdleInvalidator` (`libqdutils`),
dipanggil dari `qhwc::MDPComp::init`. Tapi saat log diambil
`init.svc.vendor.hwcomposer-2-1 = running` dan `init.svc.surfaceflinger = running`
— keduanya pulih. Perlu diawasi, bukan diperbaiki sekarang.

**Ketiadaan `system_server` di logcat** bukan bukti ia tidak pernah jalan.
**69% dari 8885 baris logcat adalah `avc: denied`**, dan satu proses
(`flags_health_check`, pid 2469) memuntahkan ratusan denial dalam milidetik yang
sama. Banjir itu menggusur baris lain dari ring buffer. Banjirnya sendiri
kemungkinan gejala dari restart-loop, jadi diperkirakan reda sendiri begitu netd
berhenti mati.

## Bootwatchdog: 120 → 300 detik

Atas permintaan. Boot 2 dipotong di detik 199 sementara netd masih berputar,
jadi tidak pernah terlihat apakah ada keadaan yang stabil setelah menit ketiga.
Pagu mutlak 600 detik **tidak** diubah, sehingga hang sungguhan tetap tertangkap.
Bisa diubah tanpa rebuild: `setprop persist.a37.bootwatchdog.timeout <detik>`.

---

## Kelemahan alat audit yang ini ungkap — sudah diperbaiki

`audit-kit21.sh` versi pertama menaruh perbaikan netd ini di kategori **BEDA**
(konteks bergeser), yang terbesar dan paling mudah dikesampingkan. Sebabnya
sepele: **berkasnya pindah**.

```
netd/NetdUpdatable.cpp        (21)
bpf/netd/NetdUpdatable.cpp    (22)
```

Patch yang berkasnya pindah gagal terap maju maupun mundur, jadi ia tidak pernah
muncul sebagai ABSEN. Alat kini punya kategori **PINDAH** sendiri yang melacak
basename ke lokasi barunya. Hasilnya langsung membongkar satu lapis utuh yang
tadinya tak terlihat — **8 patch BPF-less di `packages/modules/Connectivity`**:

```
0001-NetdUpdatable-perbaiki-kondisi-ebpf.supported  -> bpf/netd/NetdUpdatable.cpp   [SUDAH DIPORT]
0012-Revert-netdupdatable-add-back-abort-on-init    -> bpf/netd/NetdUpdatable.cpp   [SUDAH DIPORT]
0006-Allow-failing-to-load-bpf-programs             -> bpf/netd/BpfHandler.cpp
0002-netbpfload-createSysFsBpfSubDir                -> bpf/loader/NetBpfLoad.cpp
0007-Support-non-working-BPF-maps                   -> bpf/loader/NetBpfLoad.cpp
                                                       bpf/headers/include/bpf/BpfMap.h
0009-UL-DNM-netbpfload-Disable-reboot-on-failure    -> bpf/loader/netbpfload.rc
0010-UL-dnsresolver-Support-no-bpf-usecase          -> bpf/dns_helper/DnsBpfHelper.cpp
```

Sisanya sengaja belum diport. Alasannya berbasis bukti, bukan penghematan:
`init.svc.bpfloader = stopped` dengan `bpf.progs_loaded=1` (bpfloader platform
sudah selesai normal), dan `DnsBpfHelper` mengembalikan `EUNATCH` alih-alih
abort. Jadi tidak ada di antaranya yang terbukti fatal pada boot ini.

### Prediksi yang saya buat, lalu terbukti salah

Saya menduga penghalang berikutnya adalah `BpfNetMaps` di `system_server`:
`ConnectivityService.java:1979` membuatnya saat boot, konstruktornya memanggil
`ensureInitialized` -> `initBpfMaps()`, dan getternya melempar
`IllegalStateException("Cannot open netd configuration map")`. Tanpa
`CONFIG_BPF_SYSCALL` peta itu memang tidak bisa dibuka, jadi kelihatannya pasti
menjatuhkan `system_server`.

Sebelum menambal 25 titik pemakaian secara buta, saya periksa konstruktornya —
dan ternyata **sudah berpagar**:

```java
try {
    ensureInitialized(context);
} catch (Throwable t) {
    android.util.Log.e("PHH", "Failed initialization BpfMaps, doing without it", t);
}
```

Tag `"PHH"` menandakan asalnya dari patchset **trebledroid** yang memang sudah
diterapkan, dan ia lengkap: **20 penjaga null** tersebar di seluruh berkas
(`sUidOwnerMap == null` dsb.) sehingga metode-metodenya aman dipanggil tanpa peta.

Dua pelajaran. Pertama, menambal itu buta akan mubazir sekaligus berbahaya —
beberapa metode mengembalikan default **firewall**, dan menebak salah di sana
punya implikasi keamanan. Kedua, ini menjelaskan bentuk celahnya: trebledroid
menutup lapis **Java/framework** BPF-less dengan rapi, tapi tidak menyentuh
`libnetd_updatable` yang **native** — dan persis di situlah satu-satunya
kebocoran berada.

Angka audit setelah perbaikan: **23 SUDAH, 33 ABSEN, 14 PINDAH, 68 BEDA**.
