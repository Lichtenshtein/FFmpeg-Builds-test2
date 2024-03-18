#!/bin/bash

SCRIPT_REPO="https://github.com/MartinEesmaa/xevd"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {

    if [ ! -f "version.txt" ]; then
    echo v0.4.1 >> version.txt
    else
    :
    fi
    
    mkdir build && cd build

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" ..
    make -j$(nproc)
    make install
}

ffbuild_configure() {
    echo --enable-libxevd
}

ffbuild_unconfigure() {
    echo --disable-libxevd
}
