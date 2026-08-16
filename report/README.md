# report/ — bukti mentah dari perangkat

Log yang mendasari `DIAGNOSIS-boot1.md` .. `DIAGNOSIS-boot3.md`. Disimpan utuh
supaya setiap klaim di dokumen itu bisa ditelusuri sendiri, bukan dipercaya
begitu saja.

| Folder | ROM | Tertahan | Akar |
|---|---|---|---|
| `bootfail1` | `...071019...` | 120 s | `rename()` -> `renameat2` ENOSYS, `BOOTCLASSPATH` kosong |
| `bootfail2` | `...075116...` | 199 s | `netd` abort di `BpfHandler::init` |
| `bootfail3` | `...082617...` | 370 s | `system_server` abort di `JNI_OnLoad` (`ClatCoordinator`) |

Build sesudahnya, `...100715...`, boot sampai homescreen.

## Isi tiap folder

| Berkas | Catatan |
|---|---|
| `logcat.txt` | **69% isinya `avc: denied`** di bootfail2 — ring buffer terbanjiri sampai baris berguna tergusur. Ketiadaan sebuah pesan di sini bukan bukti |
| `getprop.txt` | `init.svc.*` paling menentukan: `running` vs `restarting` |
| `dmesg.txt` | hanya mencakup detik-detik terakhir, sebab yang sama |
| `console-ramoops-0` | di `bootfail1` ini berasal dari sesi **TWRP**, bukan dari boot yang gagal — tidak relevan |
| `pmsg-ramoops-0` | log userspace yang bertahan lewat reboot hangat |
| `environ.txt` | `/data/system/environ/` — pembeda kunci boot 1 (`classpath` vs hanya `.tmp`) |
| `tertahan-detik.txt` | ditulis `bootwatchdog.sh` sebelum reboot ke recovery |
| `last_kmsg.txt` | kosong di ketiganya |

## Peringatan

Berkas ini memuat **nomor seri perangkat** (`ro.serialno`, `ro.boot.serialno`)
di `getprop.txt`. Disertakan atas keputusan sadar pemilik perangkat. Tidak ada
IMEI, alamat MAC, maupun SSID.

## Jangan tertukar

Komentar di `bootwatchdog.sh` menyebut `report/bootfail3/` yang merujuk folder
milik **proyek LOS 21**, bukan `bootfail3` di sini. Keduanya kebetulan bernama
sama dengan isi yang sama sekali berbeda.
