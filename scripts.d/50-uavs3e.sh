#!/bin/bash

SCRIPT_REPO="https://github.com/MartinEesmaa/uavs3e.git"

ffbuild_enabled() {
    [[ $TARGET == win32 ]] && return -1
    [[ $TARGET == winarm64 ]] && return -1
    return 0
}

ffbuild_dockerbuild() {
    mkdir build/linux
    cd build/linux

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DCOMPILE_10BIT=1 -DCOMPILE_FFMPEG=ON -DBUILD_SHARED_LIBS=NO ../..
    make -j$(nproc)
    make install

    cp -f "$FFBUILD_PREFIX"/include/uavs3e/uavs3e.h "$FFBUILD_PREFIX"/include
    cp -f "$FFBUILD_PREFIX"/include/uavs3e/com_api.h "$FFBUILD_PREFIX"/include
}

ffbuild_configure() {
    echo --enable-libuavs3e
}

ffbuild_unconfigure() {
    (( $(ffbuild_ffver) > 700 )) || return 0
    echo --disable-libuavs3e
}
