#!/bin/bash

SCRIPT_REPO="https://github.com/bplaum/gavl.git"
SCRIPT_COMMIT="7f7b52bcde6bda8908f859ffa1c3619f7100bab8"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    CFLAGS="$CFLAGS" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS" \
    LDFLAGS="$LDFLAGS" \
    LIBS="$LIBS" \
    ./configure \
        --prefix="$FFBUILD_PREFIX" \
        --host="$FFBUILD_TOOLCHAIN" \
        --disable-shared \
        --enable-static \
        --with-pic \
        --without-doxygen || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1
}
