#!/bin/bash

SCRIPT_REPO="https://svn.xvid.org/trunk/xvidcore"
SCRIPT_REV="2202"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "retry-tool svn --non-interactive checkout --username 'anonymous' --password '' '${SCRIPT_REPO}@${SCRIPT_REV}' . --quiet"
}

ffbuild_dockerbuild() {
    cd build/generic

    # The original code fails on a two-digit major...
    # sed -i\
        # -e 's/GCC_MAJOR=.*/GCC_MAJOR=10/' \
        # -e 's/GCC_MINOR=.*/GCC_MINOR=0/' \
        # configure.in

    # Фикс для современных GCC (Xvid не понимает двузначные числа)
    sed -i 's/GCC_MAJOR=.*/GCC_MAJOR=14/' configure.in
    sed -i 's/GCC_MINOR=.*/GCC_MINOR=0/' configure.in

    ./bootstrap.sh

    # Xvid падает с LTO, отключаем его для этого скрипта
    export CFLAGS="${CFLAGS/-flto=auto/} -fno-lto -std=gnu99"
    export LDFLAGS="${LDFLAGS/-flto=auto/} -fno-lto"

    ./configure \
        --prefix="$FFBUILD_PREFIX" \
        --host="$FFBUILD_TOOLCHAIN" \
        --disable-shared --enable-static

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Удаляем остатки DLL, если они вдруг собрались (для Win64)
    rm -f "$FFBUILD_DESTPREFIX"/{bin/libxvidcore.dll,lib/libxvidcore.dll.a}
    # rm -f "$FFBUILD_DESTPREFIX"/lib/*.dll*
}

ffbuild_configure() {
    echo --enable-libxvid
}

ffbuild_unconfigure() {
    echo --disable-libxvid
}
