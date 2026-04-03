#!/bin/bash

SCRIPT_REPO="https://github.com/uavs3/uavs3d.git"
SCRIPT_COMMIT="0e20d2c291853f196c68922a264bcd8471d75b68"

ffbuild_enabled() {
    [[ $TARGET == win32 ]] && return 1
    [[ $TARGET == winarm64 ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    mkdir build/linux
    cd build/linux

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DCOMPILE_10BIT=1 \
        -DBUILD_SHARED_LIBS=NO ../.. || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

}

ffbuild_configure() {
    echo --enable-libuavs3d
}

ffbuild_unconfigure() {
    echo --disable-libuavs3d
}
