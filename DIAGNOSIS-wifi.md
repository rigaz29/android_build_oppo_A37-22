# Wi-Fi mentok di "obtaining IP address" — rute, bukan DHCP

Artefak: `report/wifi/`. Diambil setelah adb USB berfungsi, jadi ini kegagalan
pertama yang bisa didiagnosis dari perangkat hidup, bukan dari reruntuhan boot.

## Labelnya menyesatkan: DHCP justru BERHASIL

```
D DhcpClient: Broadcasting DHCPREQUEST ciaddr=0.0.0.0 request=192.168.0.196
D DhcpClient: Received packet: ACK: your new IP /192.168.0.196,
              netmask /255.255.255.0, gateways [/192.168.0.1]
D DhcpClient: Confirmed lease: DHCP server /192.168.0.1
D DhcpClient: Scheduling renewal in 43199s
```

Lease sah dan lengkap. Yang gagal terjadi **20 milidetik** sesudahnya:

```
12:30:08.883  netd: interfaceSetCfg(wlan0, ipv4Addr: 192.168.0.196)   <- alamat terpasang
12:30:08.903  ConnectivityService: Exception in addRoute for non-gateway:
                                   ServiceSpecificException: Machine is not on the network
12:30:08.905  ConnectivityService: Exception in addRoute for gateway:      (sama)
12:30:08.906  ConnectivityService: Setting DNS servers for network 104 to []
```

`Machine is not on the network` = **ENONET**. Rute ditolak, DNS jadi kosong,
jaringan tidak pernah bisa dipakai. 18 detik kemudian framework menyerah:

```
12:30:26.788  wpa_supplicant: CTRL-EVENT-DISCONNECTED reason=3 locally_generated=1
12:30:26.850  ConnectivityService: [104 WIFI] going from CONNECTING to DISCONNECTED
```

`locally_generated=1` — perangkat yang memutus, bukan AP. Lalu siklusnya
berulang. Karena state tidak pernah mencapai CONNECTED, UI terus menampilkan
"obtaining IP address" padahal IP-nya sudah lama didapat.

Konsisten dengan keadaan saat log diambil: `wlan0: <NO-CARRIER> state DOWN` dan
`ip route` **kosong sama sekali**, sementara penghitung paket menunjukkan
RX 57 / TX 57 — pertukaran memang sempat terjadi.

## Akar

Rute lewat gateway hanya bisa dipasang kalau sudah ada rute langsung-terhubung
yang mencakup gateway itu. Kernel membuat rute semacam itu di tabel **`main`**
saat alamat dipasang, sementara netd bekerja di tabel **per-jaringan** — dan
tidak ada aturan yang menyuruhnya menoleh ke `main`.

Perbaikannya menambahkan aturan itu pada prioritas 30000
(`RouteController.cpp`, dari kit LOS 21). Komentar hulunya menggambarkan
kegagalan kita kata per kata:

> *"in order to add the route, there must already be a directly-connected route
> that covers the gateway"*

## Yang saya keliru lebih dulu

Kandidat ini sempat saya **singkirkan** dengan alasan `TARGET_NEEDS_NETD_DIRECT_CONNECT_RULE`
tidak dipakai di device tree, tidak ada di `vendor/lineage`, dan tidak ada di
`netd`. Kesimpulan itu terbalik: flag itu tidak dipakai justru karena
dukungannya belum ada, bukan karena tidak diperlukan.

## Penyesuaian terhadap kit LOS 21

Kit memasang define lewat `soong_config_module_type` di namespace
`lineageGlobalVars`. Namespace itu sudah dicabut hulu di 22, jadi define dipasang
langsung sebagai `cppflags` pada `libnetd_server` — modul yang memang membangun
`RouteController.cpp`.

Terverifikasi di `build.lineage_A37.7.ninja`: define hadir di `cFlags` seluruh
varian `libnetd_server`, termasuk `_static_cfi` yang menghasilkan objeknya.

## Jebakan verifikasi yang hampir menyesatkan saya

**Ninja di pohon ini terpecah 11 berkas** (`build.lineage_A37.0.ninja` ..
`.9.ninja` plus yang utama). Memeriksa satu berkas saja menghasilkan `0`
kemunculan dan kesimpulan keliru bahwa perbaikannya tidak aktif. Sapu
`build.lineage_A37*.ninja`, jangan satu berkas.

Dan **simbol `addDirectlyConnectedRule` tidak sah dijadikan patokan**: fungsinya
dipanggil sekali sehingga wajar di-inline dan simbolnya lenyap. Ketiadaannya
bukan bukti. Karena itu gerbang di `tools/verify-ship.sh` membuktikan
**asal-usul** — sha256 `netd` di dalam zip harus sama dengan biner hasil build —
sementara keaktifan define diverifikasi di tingkat build lewat cFlags.

## Yang sengaja TIDAK disentuh

Log juga memuat `ERROR unparsable netlink msg` berulang. Pesannya sudah didekode
dan **sah**: `RTM_NEWADDR` (tipe 0x14) untuk `wlan0` (ifindex 29), prefixlen 24,
alamat 192.168.x.x. Jadi parser Android 15 yang menolaknya, bukan pesannya yang
rusak.

Patch LOS 21 untuk ini satu baris (`mNetlinkEventParsingEnabled = false`) tapi
**tidak berlaku**: flag itu sudah dicabut di 22 dan `RTM_NEWADDR` justru
ditangani parser-nya, jadi inkompatibilitasnya lebih halus.

Tidak ditambal buta. Kalau setelah perbaikan rute Wi-Fi jalan, ini memang
sekadar berisik. Kalau masih putus di detik ke-18 yang sama, barulah ia jadi
sasaran berikutnya — dengan bukti baru.

## Hasil

```
lineage-22.2-20260816_134145-UNOFFICIAL-A37.zip   754.085.134 B
sha256 31cda97066b4ce4ffa3ec7035514283799bc5e19710c661d164512e41d46b982
```

Sembilan gerbang `tools/verify-ship.sh` lolos dari zip yang dikirim.
