#!/bin/bash

SCRIPT_REPO="https://github.com/bplaum/gavl.git"
SCRIPT_COMMIT="f798ff76f6a4252f92cd209a1c973126e9673691"

ffbuild_depends() {
    echo gmp
    echo openssl # may be enabled
    echo nettle
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    ./autogen.sh

    export PKG_CONFIG_PATH="$FFBUILD_PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-shared
        --enable-static
        --with-pic
        --without-doxygen
        # если будут ошибки ассемблера
        # --disable-simd
    )

    CFLAGS="$CFLAGS" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS" \
    LDFLAGS="$LDFLAGS" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1
}
