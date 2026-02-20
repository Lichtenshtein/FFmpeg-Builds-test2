#!/bin/bash

SCRIPT_REPO="https://git.savannah.gnu.org/git/libcdio.git"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    autoreconf -if

    # вставляем макросы прямо в заголовочный файл, который включают все
    find include/cdio -name "*.h" -exec sed -i '1i#ifndef _POSIX_C_SOURCE\n#define _POSIX_C_SOURCE 199309L\n#endif' {} +

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
    )

    ./configure "${myconf[@]}" CFLAGS="$CFLAGS -D_POSIX_C_SOURCE=199309L"

    make -j$(nproc) $MAKE_V MAKEINFO=true
    make install DESTDIR="$FFBUILD_DESTDIR" MAKEINFO=true $MAKE_V
}
