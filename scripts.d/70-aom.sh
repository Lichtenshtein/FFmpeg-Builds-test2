#!/bin/bash

SCRIPT_REPO="https://gitlab.com/damian101/aom-psy101.git"
SCRIPT_COMMIT="6a3435223b36b29e6cc9815b1f86720dcaba57f6" 

ffbuild_depends() {
    echo vmaf
    echo zlib
    echo libavif
    echo libjxl
}

ffbuild_enabled() {
    [[ $VARIANT == lgpl* ]] && return 1
    [[ $TARGET == winarm64 ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p _build && cd _build

    local myconf=(
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DENABLE_EXAMPLES=OFF
        -DENABLE_TESTS=OFF
        -DENABLE_DOCS=OFF
        -DENABLE_TOOLS=OFF
        -DENABLE_TESTDATA=OFF
        -DENABLE_WERROR=OFF
        -DENABLE_CCACHE=ON
        -DENABLE_NASM=ON
        -DCONFIG_TUNE_VMAF=1
        -DCONFIG_AV1_TEMPORAL_DENOISING 1 # def 0
        -DCONFIG_BITRATE_ACCURACY 1 # def 0
        -DCONFIG_SALIENCY_MAP 0 # saliency map based encode tuning for VMAF; def 0
        -DCONFIG_CWG_C013 1 # Support for 7.x and 8.x levels; def 0
        -DCONFIG_TFLITE 1 # tenserflow-lite static
        -DCONFIG_THREE_PASS 0 # Enable three-pass encoding; def 0, try 1?
        -DCONFIG_HIGHWAY 1 # Use Highway for SIMD; def 0 # hwy donored from libjxl
        -DCONFIG_NN_V2 0 # Fully-connected neural nets ver.2; def 0
        -DCONFIG_AV1_DECODER=1
        -DCONFIG_AV1_ENCODER=1
        -DCONFIG_TUNE_BUTTERAUGLI=1 # need libjxl
        -DCONFIG_LIBYUV=1 # need libavif
        -DCONFIG_PIC=1
        -DCONFIG_RUNTIME_CPU_DETECT=1
        -DCONFIG_AV1_HIGHBITDEPTH=1
        -DCONFIG_SALIENCY_MAP=1
        # можно выключить и не тянуть лишний код контейнеров внутрь библиотеки
        -DCONFIG_WEBM_IO=1
    )

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # Добавляем VMAF в pkg-config, иначе FFmpeg не соберется статикой
    echo "Requires.private: libvmaf libyuv" >> "$PC_DIR/aom.pc"
}

ffbuild_configure() {
    echo --enable-libaom
}

ffbuild_unconfigure() {
    echo --disable-libaom
}
