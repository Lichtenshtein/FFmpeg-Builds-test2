# FFmpeg Static Auto-Builds

Static Windows (x86_64) and Linux (x86_64) Builds of ffmpeg master and latest release branch.

Windows builds are targetting Windows 7 and newer, provided UCRT is installed.
The minimum supported version is Windows 10 22H2, no guarantees on anything older.

Linux builds are targetting RHEL/CentOS 8 (glibc-2.28 + linux-4.18) and anything more recent.

Sometimes rarely I had to manually fix older compatibility issues like Windows from coming external features.

## Features of Martin Eesmaa's custom FFmpeg automated builds

- External support to SVT encoders of HEVC and VP9
- Includes nonfree binaries with fdkaac (Fraunhofer AAC library)
- Dolby AC4 native experimental decoding support
- Apple AAC AudioToolbox encoder support (Windows only, requires iTunes or 8 dll files*)
- Additional automated Windows builds of x86 and ARM64.
- Additional external features follows libbsb2, CD reading, ModPlug, QR encoding/decoding.
- External features of video by AVS3, Fraunhofer HHI VVDEC, AVS, MPEG-5 EVC, MPEG-5 LCEVC decoder.
- External features of audio by ILBC, Google LC3, Microsoft GSM, MP3 Shine, Speex, AMR-WB, CELT and MPEG-H 3D Audio encoder from Ittiam.

Implement missing features in future:

```
ladspa lcms2 libcodec2 libdc1394 libflite
libglslang libiec61883 libklvanc liblensfun
libopencv libopenvino librsvg libtensorflow 
libtesseract libtorch opengl librabbitmq 
```

Old features or some errors due to compilation or/and limited which didn't fit:

* `libcaca` - Only Linux builds works, but Windows compilation error.
* `libsvtjpgxs` - Segmentation error after test of encode and also decoding shows weird corrupted image result of code on FFplay.
* `libdatachannel` - Compilation error for reason undefined reference.
* `librtmp` - No need to enable external RTMP feature, FFmpeg has already have native RTMP feature implemented.
* `libklvanc` - Windows build failed to compile, but Linux works and it is not yet enabled until DeckLick Linux feature is available.
* `libsmbclient` - Too complicated for to install little bit, later...
* `libmpeghdec` - Only Windows & Linux 64-bit architectures works, but others are not working due to error compilations.

For AudioToolbox encoder, it is only Windows support.

Two choices for to install [iTunes](https://www.apple.com/itunes/) or use portable DLL files from iTunes without installed which is called [QTFiles](https://github.com/AnimMouse/QTFiles).

Note: Install iTunes using Windows version, but Microsoft Store version may be not kinda sure.

Or another method is to install [QTFiles](https://github.com/AnimMouse/QTFiles) for iTunes DLL portables for use QAAC and FFmpeg, see the instructions by link.

The third option is you can manually copy DLL files from iTunes:

DLL files without iTunes installed needs require 8 DLL files to order encoder `aac_at`:

It can be found on: `C:\Program Files\iTunes\`:

```
CoreAudioToolbox.dll libdispatch.dll CoreFoundation.dll objc.dll libicuin.dll ASL.dll libicuuc.dll icudt62.dll
```

**Hint:** You can copy these DLL files from iTunes right next to qaac.exe or/and ffmpeg.exe.

## Fraunhofer IIS MPEG-H decoder

REMINDER: This didn't work due to xHE-AAC audio files were not playing when mpeghdec external feature is enabled connected to libFDK modified source. I will reenable it once I fixed to mpeghdec problem again. I apology with that. :(

Description: Experimental Fraunhofer IIS MPEG-H 3D Audio decoding support (requires command argument: `-channel_layout`)

Please note that FFmpeg doesn't have demux support of MPEG-H 3D Audio channels only.

You can only decode via command argument `-channel_layout`.

For example, ensure to have MediaInfo for audio channels count:

```
# Mono audio channel file
ffmpeg_vvceasy -channel_layout mono -i MHM.mp4 MHM.wav
# Stereo audio channel file
ffmpeg_vvceasy -channel_layout stereo -i MHM.mp4 MHM.wav
```

See the more info of manual standard channel layouts [here](https://trac.ffmpeg.org/wiki/AudioChannelManipulation#Listchannelnamesandstandardchannellayouts).

## Package List

For a list of included dependencies check the scripts.d directory.
Every file corresponds to its respective package.

## How to make a build

### Prerequisites

* bash
* docker

### Build Image

* `./makeimage.sh target variant [addin [addin] [addin] ...]`

### Build FFmpeg

* `./build.sh target variant [addin [addin] [addin] ...]`

On success, the resulting zip file will be in the `artifacts` subdir.

### Targets, Variants and Addins

Available targets:
* `win64` (x86_64 Windows)
* `win32` (x86 Windows)
* `linux64` (x86_64 Linux, glibc>=2.28, linux>=4.18)
* `linuxarm64` (arm64 (aarch64) Linux, glibc>=2.28, linux>=4.18)

The linuxarm64 target will not build some dependencies due to lack of arm64 (aarch64) architecture support or cross-compiling restrictions.

* `davs2` and `xavs2`: aarch64 support is broken.
* `libmfx` and `libva`: Library for Intel QSV, so there is no aarch64 support.

Available variants:
* `gpl` Includes all dependencies, even those that require full GPL instead of just LGPL.
* `lgpl` Lacking libraries that are GPL-only. Most prominently libx264 and libx265.
* `nonfree` Includes fdk-aac in addition to all the dependencies of the gpl variant.
* `gpl-shared` Same as gpl, but comes with the libav* family of shared libs instead of pure static executables.
* `lgpl-shared` Same again, but with the lgpl set of dependencies.
* `nonfree-shared` Same again, but with the nonfree set of dependencies.

All of those can be optionally combined with any combination of addins:
* `4.4`/`5.0`/`5.1`/`6.0`/`6.1`/`7.0`/`7.1` to build from the respective release branch instead of master.
* `debug` to not strip debug symbols from the binaries. This increases the output size by about 250MB.
* `lto` build all dependencies and ffmpeg with -flto=auto (HIGHLY EXPERIMENTAL, broken for Windows, sometimes works for Linux)

### Testet dependency chains for manual builds

* `The System Core` (Foundation; always build first). Without this, nothing will work.

```
10-mingw|10-mingw-std-threads|15-base|20-zlib|
```

* `librsvg`
```
10-mingw|10-mingw-std-threads|15-base|20-zlib|20-libiconv|21-gettext|20-pcre2|20-pixman|24-libffi|25-freetype|25-fribidi|25-libpng|25-bzlib|24-xz|25-libxml2|25-glib2|35-fontconfig|35-harfbuzz|38-brotli|40-freetype|39-cairo|40-pango|44-dav1d|45-librsvg-cargo-test
```