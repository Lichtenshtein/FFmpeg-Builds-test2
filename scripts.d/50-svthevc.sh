#!/bin/bash

SCRIPT_REPO="https://github.com/OpenVisualCloud/SVT-HEVC"

ffbuild_enabled() {
    return 0
}

fixarm64=()

ffbuild_dockerbuild() {

    mkdir build1 && cd build1

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" -DBUILD_SHARED_LIBS=OFF ..
    make -j$(nproc)
    make install
}

ffbuild_configure() {
    echo --enable-libsvthevc
}

ffbuild_unconfigure() {
    echo --disable-libsvthevc
}
