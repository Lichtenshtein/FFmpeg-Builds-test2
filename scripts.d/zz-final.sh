#!/bin/bash

SCRIPT_SKIP="1"

ffbuild_depends() {
    echo libiconv
    echo zlib
    echo bzlib
    echo fribidi
    echo gmp
    echo libxml2
    echo openssl
    echo freetype
    echo fontconfig
    echo harfbuzz
    echo xz
    echo tbbmalloc
    echo libavif
    echo nettle
    echo quiche
    echo nghttp2
    echo freeglut
    echo libxxhash
    echo libmpg123
    echo cryptopp
    echo soundtouch
    echo gnutls
    echo openvino_shared
    # echo lcevcdec
    echo spirv-tools
    echo gavl
    echo lcevcdec
    echo libvorbis
    echo opencl
    echo jbigkit
    echo libicu
    echo pulseaudio
    echo vmaf
    echo x11
    echo curl
    echo vulkan-headers
    echo vulkan-loader
    echo shaderc
    echo spirv-cross
    echo spirv-headers
    echo libunibreak
    echo enable
    echo amf
    echo aom
    echo libaribb
    echo libpng
    echo audiotoolbox
    echo avisynth
    echo bs2b
    echo cdiowpar
    echo cdio
    echo chromaprint
    echo dav1d
    echo davs2
    echo decklink
    echo libdvdcss
    echo libdvdread
    echo libdvdnav
    echo libtiff
    echo libjpeg-turbo
    echo fdk-aac
    echo giflib
    echo ffnvcodec
    echo flite
    echo frei0r
    echo gme
    echo ilbc
    echo kvazaar
    echo glslang
    echo lc3
    echo lensfun
    echo libaribcaption
    echo libass
    echo libbluray
    echo libcaca
    echo libcelt
    echo libcodec2
    echo libarchive
    echo libgsm
    echo brotli
    echo lcms2
    echo libjxl
    echo libklvanc
    echo zstd
    echo libmad
    echo libmp3lame
    echo libmpeghdec
    echo libmysofa
    echo libopus
    echo libplacebo
    echo librist
    echo librsvg
    echo libssh
    echo libtheora
    echo libtorch
    echo libvpx
    echo libwebp
    echo libzmq
    echo lv2
    echo serd
    echo zix
    echo sord
    echo sratom
    echo lilv
    echo mbedtls
    echo librist
    echo pango
    echo cairo
    echo modplug
    echo mp3shine
    echo mpeghe
    echo nnedi3
    echo onevpl
    echo openal
    echo openapv
    echo opencore-amr
    echo opencv
    echo opengl
    echo openh264
    echo openjpeg
    echo openmpt
    echo openvino
    echo pocketsphinx
    echo qrencode
    echo quirc
    echo librabbitmq
    echo rav1e
    echo rubberband
    echo schannel
    echo sdl
    echo snappy
    echo soxr
    echo speex
    echo srt
    echo svtav1
    echo svthevc
    echo svtjpegxs
    echo svtvp9
    echo libtensorflow
    echo libtesseract
    echo twolame
    echo uavs3d
    echo uavs3e
    echo libpciaccess
    echo libdrm
    echo libva
    echo finalize
    echo vapoursynth
    echo vidstab
    echo vo-amrwb
    echo vvdec
    echo vvenc
    echo wasapi
    echo whisper
    echo x264
    echo x265
    echo xavs
    echo xavs2
    echo xevd
    echo xeve
    echo xvid
    echo zimg
    echo zvbi
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerfinal() {
    return 0
}

ffbuild_dockerdl() {
    return 0
}

ffbuild_dockerlayer() {
    return 0
}

ffbuild_dockerstage() {
    return 0
}

ffbuild_dockerbuild() {
    return 0
}

ffbuild_ldexeflags() {
    return 0
}
