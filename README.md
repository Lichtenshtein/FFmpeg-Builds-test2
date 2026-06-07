## FFmpeg Custom Build

This fork is an advanced FFmpeg build system architecture using GCC 14 and Ubuntu 24.04.

### Key changes and improvements:

- Architectural optimization: All components are built with the -march=broadwell -mtune=broadwell -O3 flags, which ensures maximum performance on Xeon E5 v4 series processors.

- Docker Build Kit Infrastructure: Using --mount=type=cache for ccache and downloads, which reduces rebuild time on GitHub Actions by 60-80%.

- LTO (Link Time Optimization) support: Stable LTO support for Windows (MinGW) has been implemented, which allows you to reduce the size of binaries and increase code execution speed through inter-module optimization.

### Successfully Implemented:

- Improved AI and OCR integration: Tesseract OCR 5.x: Full OCR support (including Leptonica, Pango, Cairo and Libarchive dependencies).

- Libflite: Integration of Speech Synthesis with support for all built-in voices (including CMU Arctic).

- QTFiles Automation: The build now automatically includes and packages the necessary DLLs (CoreAudioToolbox, etc.) from the QTFiles project, allowing the aac_at encoder to work out of the box without installing iTunes.

- Fixed dependency chains: Successfully resolved compilation issues for complex components such as libarchive (with CNG/Crypto support) and zstd (with multithreading support).

- zstd (v1.6.0): Implemented full multithreading support (ZSTD_MULTITHREAD) for Windows. Optimized for BMI2 (Xeon Broadwell) instructions. Fixed critical CMake configuration error (CXX initialization). Static linking with correct forwarding -lpthread to libzstd.pc.

- libarchive (v3.7.x): Includes support for Windows CNG (Crypto Next Generation) for hardware encryption. Integrated support for formats: zstd, xz, bzip2, openssl and libxml2. Cleared of unnecessary utilities (bsdtar/bsdcpio), leaving only a clean static library for FFmpeg.

- lcms2 (v2.18): Built with support for multithreading (threaded) and acceleration of floating point calculations (fast_float). Full static linking, optimized for SSE2 and modern Broadwell instructions.

- librsvg (Cargo-based): Completed cross-compiled Rust build chain, including cairo and pango dependencies.

- Kvazaar with Crypto++ support.

- LCEVC Decoder SDK with a fully natively generated SPIR-V shaders within a cross-compilation environment - compiled with full Vulkan pipeline.

- Whisper with Vulkan and OpenVINO support.

- x265 with optional SVT-HEVC 1.5.1 as core for compliant bitstreams. [Link](https://bitbucket.org/multicoreware/x265_git/src/master/doc/reST/svthevc.rst)

- VapourSynth (Core + VSScript + Python-runtime) r75 compiled and isolated from the system.

- znedi3 (high performance nnedi3 via zimg) Avisynth filter compiled.

- frei0r with facerecognition plugins and all OpenCV/Cairo/Gavl filters.

- libmp3lame with libmpg123 as a Decoder and SIMD Optimized LAME Encoder.

- libvorbis with aoTuV 2021 and Lancer patch.

- libopus with DRED, OSCE and custom modes enabled.

- OpenVINO built and linked statically with Intel CPU and Intel GPU (optionally) support.

### Implementation status:

Added to the current build:

[x] libflite (Speech Synthesis)
[x] zstd (libzstd with activated multithreading for static builds)
[x] libarchive (Universal Archive Support)
[x] lcms2 (Little CMS)
[x] pango / cairo (Advanced Text Rendering)
[x] libtesseract (OCR Engine)

---

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

### Test dependency chains for manual builds

* `The System Core` (Foundation; always build first). Without this, nothing will work.

```
01-mingw-std-threads|02-mingw|03-base|08-zlib|27-freeglut
```

* `glib2`
```
05-libicu|06-libiconv|07-gettext|08-zlib|11-bzlib|12-libffi|15-pcre2|16-glib2
```

* `librsvg`
```
06-libiconv|07-gettext|08-zlib|11-brotli|11-bzlib|11-xz|12-libffi|14-freetype|15-pcre2|16-glib2|16-libxml2|17-harfbuzz|37-libpng|39-fontconfig|39-fribidi|39-pixman|40-cairo|40-harfbuzz|41-freetype|43-pango|44-dav1d|44-svtav1|45-libavif|45-librsvg
```

* `libtesseract`
```
05-libicu|06-libiconv|07-gettext|08-zlib|11-brotli|11-bzlib|11-xz|11-zstd|12-jbigkit|12-libffi|14-freetype|15-pcre2|16-glib2|16-libxml2|17-harfbuzz|30-openssl|32-libssh|32-quiche|33-nghttp2|34-curl|37-giflib|37-libjpeg-turbo|37-libpng|37-libtiff|37-openjpeg|38-libwebp|39-fontconfig|39-fribidi|39-libtiff|39-pixman|40-cairo|40-harfbuzz|40-lcms2|42-libarchive|43-pango|59-leptonica|62-libtesseract
```

* `vulkan` (shaderc downloads, installs and compiles 'spirv-headers', 'spirv-tools', 'glslang' itself: 49-vulkan-headers|51-spirv-cross|52-shaderc|52-vulkan-loader).
```
49-vulkan-headers|50-spirv-headers|50-spirv-tools|51-spirv-cross|52-shaderc|52-vulkan-loader|99-enable
```

* `libplacebo`
```
08-zlib|27-freeglut|40-lcms2|49-vulkan-headers|51-spirv-cross|52-shaderc|52-vulkan-loader|53-libplacebo
```

* `libavif`
```
44-dav1d|44-svtav1|45-libavif
```

* `libSDL2`
```
06-libiconv|07-gettext|08-zlib|11-bzlib|12-libffi|15-pcre2|16-glib2|16-fftw3|27-freeglut|30-openssl|49-vulkan-headers|51-spirv-cross|52-shaderc|52-vulkan-loader|64-libsamplerate|64-soxr|65-pulseaudio|66-sdl
```

* `opencv`
```
04-tbbmalloc|06-libiconv|07-gettext|08-zlib|11-brotli|11-bzlib|11-xz|11-zstd|12-jbigkit|37-giflib|37-libjpeg-turbo|37-libpng|37-libtiff|37-openjpeg|38-libwebp|39-libtiff|40-lcms2|44-dav1d|44-svtav1|45-libavif|45-libjxl|49-vulkan-headers|51-spirv-cross|52-shaderc|52-vulkan-loader|59-opencl|59-openvino|61-opencv
```

* `gavl`
```
06-libiconv|08-zlib|09-gmp|11-zstd|31-nettle|32-gnutls|80-gavl
```

* `frei0r`
```
04-tbbmalloc|05-libicu|06-libiconv|07-gettext|08-zlib|09-gmp|11-brotli|11-bzlib|11-xz|11-zstd|12-jbigkit|12-libffi|14-freetype|15-pcre2|16-glib2|16-libxml2|17-harfbuzz|27-freeglut|31-nettle|32-gnutls|37-giflib|37-libjpeg-turbo|37-libpng|37-libtiff|37-openjpeg|38-libwebp|39-fontconfig|39-fribidi|39-libtiff|39-pixman|40-cairo|40-harfbuzz|40-lcms2|41-freetype|44-dav1d|44-svtav1|45-libavif|45-libjxl|49-vulkan-headers|51-spirv-cross|52-shaderc|52-vulkan-loader|54-vmaf|59-opencl|59-openvino|61-opencv|80-gavl|84-frei0r
```

* `aom`
```
01-mingw-std-threads|02-mingw|05-libicu|06-libiconv|07-gettext|08-zlib|11-brotli|11-xz|16-libxml2|27-freeglut|37-giflib|37-libjpeg-turbo|37-libpng|37-libtiff|38-libwebp|40-lcms2|44-dav1d|44-svtav1|45-libavif|45-libjxl|54-vmaf|70-aom
```

* `whisper`
```
04-tbbmalloc|49-vulkan-headers|51-spirv-cross|52-shaderc|52-vulkan-loader|59-opencl|59-openvino|69-whisper
```

* `vapoursynth`
```
08-zlib|40-zimg|64-soundtouch|80-avisynth|83-vapoursynth
```

* `curl`
```
06-libiconv|07-gettext|08-zlib|11-brotli|11-xz|11-zstd|12-libffi|16-libxml2|30-openssl|32-libssh|32-quiche|33-nghttp2|34-curl
```

* `libbluray`
```
85-libudfread|86-libdvdcss|86-libdvdread|87-libdvdnav|88-libbluray
```

### Download functions memo tips

SCRIPT_REPO[1-9] - each REPO should be downloaded simultaneously or in sequence
SCRIPT_COMMIT[1-9] - commit to download from
SCRIPT_BRANCH[1-9] - processing of branches
SCRIPT_MIRROR[1-9] - only used when the primary REPO link is unavailable 
SCRIPT_MIRROR_COMMIT[1-9] - may differ if mirror is not updated in time
SCRIPT_COMMIT="v3.4.5" - specific version
SCRIPT_REV - SVN
SCRIPT_TAGFILTER - filter by tag
SCRIPT_SKIP="1" - skip script (meta-component)