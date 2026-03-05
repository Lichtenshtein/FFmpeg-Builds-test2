#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/freetype/freetype.git"
SCRIPT_COMMIT="28407bc8cd1a3da43df7b11c40bc5c24b9883ac6"

ffbuild_depends() {
    echo fontconfig
    echo freetype
    echo zlib
    echo bzlib
    echo brotli
    echo libpng
    echo harfbuzz
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-mini-clone \"https://github.com/nyorain/dlg.git\" \"master\" subprojects/dlg"
}

ffbuild_dockerbuild() {
    set -e
    ./autogen.sh

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-shared
        --enable-static
        --with-harfbuzz
        --with-png
        --with-zlib
        --with-bzip2
        --with-brotli
        --with-pic
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( --enable-lto )

    # Помогаем линкеру найти статические либы
    export LIBS="-lharfbuzz -lpng16 -lbrotlidec -lbrotlicommon -lbz2 -lz $LIBS"

    ./configure "${myconf[@]}" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Патчим .pc файл, чтобы последующие (например, FFmpeg) видели зависимости
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/freetype2.pc"
    sed -i "s|^Libs.private:.*|Libs.private: -lharfbuzz -lpng16 -lbrotlidec -lbrotlicommon -lbz2 -lz $LIBS|" "$PC_FILE"

    get_deps_list
}