#!/bin/bash

SCRIPT_REPO="https://github.com/paullouisageneau/libdatachannel"
SCRIPT_COMMIT="62eaf521b09c467c03e1cf7532142343fe7e7a49"

ffbuild_enabled() {
    (( $(ffbuild_ffver) > 701 )) || return -1
    return 0
}

ffbuild_dockerbuild() {
    git submodule update --init --recursive --depth=1
    mkdir build && cd build

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF -DNO_{EXAMPLES,TESTS}=ON -DUSE_MBEDTLS=ON ..

    make -j$(nproc)
    make install
}

ffbuild_configure() {
    echo --enable-libdatachannel
}

ffbuild_unconfigure() {
    (( $(ffbuild_ffver) > 701 )) || return 0
    echo --disable-libdatachannel
}
