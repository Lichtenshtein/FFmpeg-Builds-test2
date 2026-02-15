#!/bin/bash

SCRIPT_REPO="https://github.com/sezero/libmad.git"
SCRIPT_COMMIT="486f902c6c686eafced3450851849527e29bc7f6"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
}

ffbuild_dockerbuild() {
    # Удаляем флаг -fforce-mem, который GCC 14 не поддерживает
    sed -i 's/-fforce-mem//g' configure
    autoreconf -if

    ./configure \
        --prefix="$FFBUILD_PREFIX" \
        --host="$FFBUILD_TOOLCHAIN" \
        --disable-shared \
        --enable-static \
        --enable-fpm=64bit # Оптимизация для 64-бит

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-libmad
}

ffbuild_unconfigure() {
    echo --disable-libmad
}
