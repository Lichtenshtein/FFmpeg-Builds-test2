#!/bin/bash

SCRIPT_REPO="https://github.com/fraunhoferhhi/vvdec"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {

    mkdir build && cd build

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" ..
    make -j$(nproc)
    make install
}

ffbuild_configure() {
    echo --enable-libvvdec
}

ffbuild_unconfigure() {
    echo --disable-libvvdec
}
