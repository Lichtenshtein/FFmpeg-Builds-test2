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
    # echo lcevcdec
    echo lcevcdec-test
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
    echo flite-test
    echo frei0r
    echo gme
    echo ilbc
    echo kvazaar
    echo glslang-test
    echo lc3
    echo lensfun-test
    echo libaribcaption
    echo libass
    echo libbluray
    echo libcaca
    echo libcelt
    echo libcodec2-test
    echo libarchive
    echo libgsm
    echo brotli
    echo lcms2
    echo libjxl
    echo libklvanc-test
    echo zstd
    echo libmad
    echo libmp3lame
    echo libmpeghdec-test
    echo libmysofa
    echo libopus
    echo libplacebo
    echo librist
    echo librsvg-cargo-test
    # echo librsvg-test
    echo libssh
    echo libtheora
    echo libtorch-test
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
    echo nnedi3-test
    echo onevpl
    echo openal
    echo openapv
    echo opencore-amr
    echo opencv-test
    echo opengl-test
    echo openh264
    echo openjpeg
    echo openmpt
    echo openvino-test
    echo pocketsphinx
    echo qrencode
    echo quirc
    echo librabbitmq-test
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
    echo svtjpegxs-test
    echo svtvp9
    echo libtensorflow-test
    echo tesseract-test
    echo twolame
    echo uavs3d
    echo uavs3e
    echo libpciaccess
    echo libdrm
    echo libva
    echo finalize
    # echo vapoursynth-test
    echo vapoursynth-python-test
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

    echo rpath
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
