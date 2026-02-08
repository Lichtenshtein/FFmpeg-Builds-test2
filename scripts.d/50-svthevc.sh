#!/bin/bash

SCRIPT_REPO="https://github.com/OpenVisualCloud/SVT-HEVC"

ffbuild_enabled() {
    [[ $TARGET == win32 ]] && return -1
    [[ $TARGET == *arm64 ]] && return -1
    return 0
}

fixarm64=()

ffbuild_dockerbuild() {

    mkdir build1 && cd build1

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DBUILD_SHARED_LIBS=OFF ..
    make -j$(nproc)
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-libsvthevc
}

ffbuild_unconfigure() {
    echo --disable-libsvthevc
}
