#!/bin/bash

SCRIPT_REPO="https://git.savannah.gnu.org/git/libcdio.git"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    autoreconf -if

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

    ./configure "${myconf[@]}"

    make -j$(nproc) $MAKE_V MAKEINFO=true
    make install DESTDIR="$FFBUILD_DESTDIR" MAKEINFO=true
}
