#!/bin/bash

SCRIPT_REPO="https://github.com/sezero/libmad.git"
SCRIPT_COMMIT="486f902c6c686eafced3450851849527e29bc7f6"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    # Удаляем флаг -fforce-mem, который GCC 14 не поддерживает
    sed -i 's/-fforce-mem//g' configure
    autoreconf -if

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
        --enable-fpm=64bit || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

}

ffbuild_configure() {
    echo --enable-libmad
}

ffbuild_unconfigure() {
    echo --disable-libmad
}
