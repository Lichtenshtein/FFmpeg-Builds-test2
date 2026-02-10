#!/bin/bash

SCRIPT_REPO="https://git.savannah.gnu.org/git/libcdio.git"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    autoreconf -if

    # В MinGW clock_gettime находится в libwinpthread
    # добавляем -lpthread, чтобы линковщик нашел clock_gettime
    export LIBS="$LIBS -lpthread"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-shared
        --enable-static
        --disable-maintainer-mode
        --without-cd-drive
        --without-cd-info
        --without-cdda-player
        --without-cd-read
        --without-iso-info
        --without-iso-read
        --disable-cpp-progs
        --with-pic
    )

    ./configure "${myconf[@]}"

    # Исправление для документации, чтобы не падал make
    mkdir -p doc && touch doc/stamp-vti

    make -j$(nproc) V=1
    make install DESTDIR="$FFBUILD_DESTDIR"
}
