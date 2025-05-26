#!/bin/bash

SCRIPT_REPO="https://github.com/MartinEesmaa/LCEVCdec.git"
SCRIPT_COMMIT="cd3159e77f9fc66bd90d84b34ad3cf7d7398f8f1"

ffbuild_enabled() {
    [[ $TARGET == winarm* ]] && return -1
    (( $(ffbuild_ffver) > 701 )) || return -1
    return 0
}

ffbuild_dockerbuild() {

    mkdir build && cd build

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF -DVN_SDK_FFMPEG_LIBS_PACKAGE="" -DVN_SDK_{JSON_CONFIG,EXECUTABLES,UNIT_TESTS,SAMPLE_SOURCE}=OFF .. -G Ninja

    ninja -j$(nproc)
    ninja install
}

ffbuild_configure() {
    echo --enable-liblcevc_dec
}

ffbuild_unconfigure() {
    (( $(ffbuild_ffver) > 701 )) || return 0
    echo --disable-liblcevc_dec
}
