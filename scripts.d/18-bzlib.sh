#!/bin/bash

SCRIPT_REPO="https://gitlab.com/bzip2/bzip2.git"
SCRIPT_COMMIT="66c46b8c9436613fd81bc5d03f63a61933a4dcc3"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    mkdir build && cd build

    cmake .. -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$CFLAGS -Wno-conversion" \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DENABLE_STATIC_LIB=ON \
        -DENABLE_SHARED_LIB=OFF \
        -DENABLE_LIB_ONLY=1

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    if [[ -f "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/libbz2_static.a" ]]; then
        mv "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/libbz2_static.a" "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/libbz2.a"
    fi
}

ffbuild_configure() {
    echo --enable-bzlib
}

ffbuild_unconfigure() {
    echo --disable-bzlib
}