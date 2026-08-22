# NewPipe bisu, browser bersuara — nol decoder audio, bukan soal Opus

Gejalanya sempit: suara tidak keluar di NewPipe, sementara YouTube di browser
bawaan normal. Bentuk seperti ini menggoda untuk ditebak sebagai masalah codec
Opus, karena NewPipe memang kerap memilih stream audio WebM/Opus sedangkan
browser memakai AAC. Tebakan itu salah, dan asimetrinya justru petunjuk ke akar
yang jauh lebih besar.

## Yang membatalkan dugaan pertama

`media.metrics` mencatat setiap sesi codec. Selama NewPipe memutar video, hanya
ada **satu**:

```
{codec, (org.schabi.newpipe, 0, 10182),
  android.media.mediacodec.codec=OMX.qcom.video.decoder.avc,
  android.media.mediacodec.mime=video/avc, ...}
```

Tidak ada sesi codec audio sama sekali. Bukan gagal, bukan error — tidak pernah
dicoba. Padahal pemutarnya jelas berniat mengeluarkan suara:

```
{audio.focus, (org.schabi.newpipe, 0, 10182),
  clientName=...AudioReactor@905523b, event#=requestAudioFocus,
  focusChangeHint=AUDIOFOCUS_GAIN}
```

Dan tidak ada satu pun AudioTrack yang lahir. `dumpsys audio` selama video
berjalan hanya berisi SoundPool launcher yang idle, sementara tabel track di
`dumpsys media.audio_flinger` kosong — hanya header, tanpa baris.

Kalau ExoPlayer menemukan decoder tapi gagal membukanya, ia melempar
`DecoderInitializationException` dan pemutaran berhenti. Di sini video terus
jalan mulus. Artinya bukan decoder yang gagal dibuka, melainkan **tidak ada
decoder yang ditawarkan** untuk MIME audio itu.

## Bukti kedua, lepas dari NewPipe

Di log yang sama, tanpa aplikasi pihak ketiga terlibat:

```
W/AS.SfxHelper( 2037): onLoadSoundEffects(), Error -2147483648
                       while loading sample /product/media/audio/ui/KeypressStandard.ogg
```

SoundPool sistem gagal memuat suara sentuh. Berkasnya Ogg Vorbis (dicek dari
header: `OggS`, `vorbis`). Dan `media.metrics` menunjukkan pola yang persis sama
seperti kasus NewPipe — ekstraksi berhasil, decoder tidak pernah menyusul:

```
{extractor, (android.uid.system, 0, 1000),
  fmt=OggExtractor, mime=audio/ogg, ntrk=1}
```

Dua subsistem yang tidak berhubungan, satu bentuk kegagalan. Itu memindahkan
kecurigaan dari aplikasi ke platform.

## Akar

`dumpsys media.player` mencetak seluruh daftar decoder. Hasilnya tidak ambigu:

```
Media type 'video/3gpp'            Media type 'audio/...'
Media type 'video/avc'                  (tidak ada satu pun)
Media type 'video/mp4v-es'
Media type 'video/mpeg2'
Media type 'video/x-vnd.on2.vp8'
```

**9 tipe video, 0 tipe audio.** Bukan Opus yang hilang — AAC, MP3, Vorbis, FLAC,
semuanya tidak ada.

Dan setiap decoder yang terdaftar milik OMX vendor:

```
Decoder "OMX.qcom.video.decoder.h263"    owner: "default"
Decoder "OMX.qcom.video.decoder.avc"     owner: "default"
Decoder "OMX.qcom.video.decoder.mpeg4"   owner: "default"
...
```

Tidak ada satu pun `c2.android.*`. Padahal komponennya jelas hidup — store
software mengekspos semuanya saat HAL-nya di-dump langsung:

```
$ lshal debug android.hardware.media.c2@1.2::IComponentStore/software
C2ComponentStore: android.componentStore.platform
  Supported components:
    name: c2.android.aac.decoder     mediaType: audio/mp4a-latm
    name: c2.android.amrnb.decoder   mediaType: audio/3gpp
    ...
```

Layanannya terdaftar normal (HIDL 1.0/1.1/1.2 + AIDL, dilayani `media.swcodec`
pid 811). Jadi codec-nya ada, tapi tidak pernah sampai ke `MediaCodecList`.

Yang memutus jembatan itu satu properti:

```
$ getprop debug.stagefright.ccodec
0
```

Artinya tertulis lugas di sumbernya,
`frameworks/av/media/codec2/sfplugin/Codec2InfoBuilder.cpp:406-431`:

```cpp
// debug.stagefright.ccodec supports 5 values.
//   0 - No Codec 2.0 components are available.
//   ...
//   4 - All components are available with their normal ranks.
int option = ::android::base::GetIntProperty("debug.stagefright.ccodec", 4);
```

Nilai `0` mematikan **seluruh** Codec 2.0. Dulu itu aman: decoder audio software
disediakan `OMX.google.*`. Komponen itu dihapus di Android 12. Sejak itu
setelan ini menyisakan nol decoder audio, karena store OMX vendor hanya berisi
komponen video QCOM.

Sisa warisannya masih terlihat di `/vendor/etc/media_codecs.xml`, yang meng-
`Include` `media_codecs_google_audio.xml` — dan isi berkas itu seluruhnya nama
mati: `OMX.google.mp3.decoder`, `OMX.google.aac.decoder`,
`OMX.google.vorbis.decoder`, `OMX.google.opus.decoder`.

Sumbernya `device/oppo/A37/device.mk`, warisan device tree msm8916 era LOS 14.1
saat CCodec masih baru dan sengaja dimatikan.

## Kenapa browser tidak terdampak

Chromium membawa decoder audionya sendiri dan mendekode di dalam prosesnya, jadi
ia tidak pernah menyentuh `MediaCodecList`. NewPipe memakai ExoPlayer, yang
bergantung penuh pada daftar itu. Gejala yang tampak seperti "bug NewPipe"
sebenarnya adalah satu-satunya aplikasi yang jujur melaporkan keadaan platform.

## Perbaikan

`debug.stagefright.ccodec` `0` → `4`. `omx_default_rank=0` di bawahnya
dipertahankan supaya decoder video QCOM tetap diutamakan di atas software.

Nilai `1` sengaja tidak dipakai. Dokumentasinya menyebut mode itu menaruh
"all other components with suffix `.avc.decoder` ... ranked last" — yang berarti
mendemosi `OMX.qcom.video.decoder.avc`, satu-satunya decoder AVC berakselerasi
di perangkat ini.

## Diuji sebelum di-build

Properti `debug.*` bisa diubah saat berjalan, jadi akarnya dibuktikan tanpa
menghabiskan satu siklus build:

```
setprop debug.stagefright.ccodec 4
setprop ctl.restart media
```

Hasil: **0 → 15** tipe decoder audio (AAC, Opus, Vorbis, MP3, FLAC, AMR, G711),
`c2.android.vorbis.decoder` terpakai, dan pengguna mengonfirmasi suaranya kembali.

## Yang saya keliru lebih dulu

**Mengira cukup me-restart aplikasinya.** Setelah `setprop`, NewPipe di-force-stop
dan dijalankan ulang — masih bisu. Daftar codec tidak dibangun per aplikasi; ia
hidup di proses `mediaserver`. Baru setelah `ctl.restart media` daftarnya berubah.

**Mengira grep-nya gagal, padahal polanya.** Saat memverifikasi label sepolicy di
image, `grep 'gralloc.msm8916'` tidak menemukan apa pun dan sempat disimpulkan
sebagai kegagalan build. Di berkas hasil tertulis `gralloc\.msm8916` — titik
sebagai wildcard hanya cocok satu karakter, sedangkan di sana ada dua (`\` dan
`.`). Pencarian harfiah (`grep -F`) menemukannya. Pelajaran yang sama berlaku di
sini untuk setiap verifikasi terhadap berkas `file_contexts` dan sejenisnya.

## Efek samping yang menguntungkan

Encoder ikut kembali: **5 audio** (AAC, AMR, FLAC, Opus) dan **7 video**.
Sebelumnya nol. Artinya perekaman video — yang membutuhkan encoder audio — baru
sejak perbaikan ini punya syarat dasarnya.

## Yang perlu diawasi

Codec2 yang menyala juga membawa decoder video software VP9, HEVC, dan AV1.
Untuk AVC hardware tetap menang karena rank-nya lebih tinggi. Tapi format yang
tidak punya padanan hardware di msm8916 kini punya decoder, dan aplikasi bisa
memilihnya. Kalau video terasa tersendat di NewPipe, itu tempat pertama yang
dicurigai — bukan regresi, melainkan pilihan format yang terlalu berat.
