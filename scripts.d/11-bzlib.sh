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
    set -e
    mkdir build && cd build

    CFLAGS="$CFLAGS $CPPFLAGS -Wno-conversion" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake .. -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF ) \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DENABLE_STATIC_LIB=ON \
        -DENABLE_SHARED_LIB=OFF \
        -DENABLE_EXAMPLES=OFF \
        -DENABLE_DOCS=OFF \
        -DENABLE_APP=OFF \
        -DENABLE_STATIC_LIB_IS_PIC=ON \
        -DENABLE_LIB_ONLY=ON || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

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