#!/bin/bash

SCRIPT_REPO="https://github.com/v-novaltd/LCEVCdec.git"
SCRIPT_COMMIT="655f029d0008f00da9c976567ea159437aa86a36"

ffbuild_depends() {
    echo vulkan-headers
    echo shaderc
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    export SKIP_POST_STRIP=1

    mkdir -p build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DPC_LIBS_PRIVATE="Libs.private: -lstdc++"
        -DVN_SDK_BENCHMARK=OFF
        -DVN_SDK_DIAGNOSTICS_ASYNC=OFF
        -DVN_SDK_DOCS=OFF
        -DVN_SDK_EXECUTABLES=OFF
        -DVN_SDK_FORCE_OVERLAY=OFF
        -DVN_SDK_GENERATE_PGO=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF) # this is NOT LTO
        -DVN_SDK_LTO=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DVN_SDK_METRICS=OFF
        -DVN_SDK_PIPELINE_CPU=ON
        -DVN_SDK_PIPELINE_LEGACY=OFF # ON
        -DVN_SDK_PIPELINE_VULKAN=ON # OFF; experimental Vulkan GPU pipeline for decoding LCEVC stream
        -DVN_SDK_SAMPLE_SOURCE=OFF
        -DVN_SDK_SIMD=ON
        -DVN_SDK_SYSTEM_INSTALL=ON
        -DVN_SDK_THREADING=ON
        -DVN_SDK_TRACING=OFF
        -DVN_SDK_UNIT_TEST=OFF
        -DVN_STRIP_RELEASE=ON
        )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( -DBUILD_SHARED_LIBS=ON VN_MSVC_RUNTIME_STATIC=OFF ) || \
        myconf+=( -DBUILD_SHARED_LIBS=OFF VN_MSVC_RUNTIME_STATIC=ON )

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    rm -rf "$FFBUILD_DESTPREFIX"/share
}

ffbuild_configure() {
    echo --enable-liblcevc-dec
}

ffbuild_unconfigure() {
    echo --disable-liblcevc-dec
}
