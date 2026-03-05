#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/freetype/freetype.git"
SCRIPT_COMMIT="156c7ea38f99de0d3827d0340fe6399325ef8cc7"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-submodule-clone"
}

ffbuild_dockerbuild() {
    set -e

    ./autogen.sh

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-shared
        --enable-static
        --with-pic
        --without-harfbuzz
        --without-png
        --without-zlib
        --without-bzip2
        --without-brotli
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( --enable-lto )

    ./configure "${myconf[@]}" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Создаем симлинк для совместимости
    ln -sf freetype2.pc "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/freetype.pc"

    get_deps_list
}
