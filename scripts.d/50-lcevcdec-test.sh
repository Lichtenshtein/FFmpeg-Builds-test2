#!/bin/bash

SCRIPT_REPO="https://github.com/v-novaltd/LCEVCdec.git"
SCRIPT_COMMIT="655f029d0008f00da9c976567ea159437aa86a36"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    mkdir build
    cd build

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DBUILD_SHARED_LIBS=NO \
        -DVN_SDK_EXECUTABLES=OFF \
        -DVN_SDK_SAMPLE_SOURCE=OFF \
        -DVN_SDK_TRACING=OFF \
        -DVN_SDK_METRICS=OFF \
        -DVN_SDK_SYSTEM_INSTALL=ON \
        -DVN_SDK_PIPELINE_LEGACY=OFF \
        -DVN_SDK_PIPELINE_VULKAN=OFF \
        -DPC_LIBS_PRIVATE="Libs.private: -lstdc++" .. || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    rm -rf "$FFBUILD_DESTPREFIX"/share

}

ffbuild_configure() {
    echo --enable-liblcevc-dec
}

ffbuild_unconfigure() {
    echo --disable-liblcevc-dec
}
