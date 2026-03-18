#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/freetype/freetype.git"
SCRIPT_COMMIT="d262bd978c3ea303289153dba1ae8a6dc4ac747a"

ffbuild_depends() {
    echo brotli
    echo bzlib
    echo harfbuzz
    echo libpng
    echo librsvg
    echo zlib
    echo fontconfig
    echo freetype
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
        --with-librsvg
        --with-pic
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( --enable-lto )

    # Добавляем флаги для RSVG (он на Rust, линковка тяжелая)
    export LIBS="$(pkg-config --libs --static librsvg-2.0 harfbuzz) $LIBS"

    ./configure "${myconf[@]}" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    clean_la_files

    # Финальный аккорд для статики FFmpeg
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/freetype2.pc"
    local ALL_DEPS="-lharfbuzz-icu -lharfbuzz-subset -lharfbuzz-vector -lharfbuzz-raster -lharfbuzz -lharfbuzz-cairo -lsicuin -lsicuuc -lsicudt -lrsvg-2 -lpng16 -lbrotlidec -lbrotlicommon -lbz2 -lz $LIBS"
    sed -i "s|^Libs.private:.*|Libs.private: $ALL_DEPS|" "$PC_FILE"

    get_deps_list
}

ffbuild_configure() {
    echo --enable-libfreetype
}

ffbuild_unconfigure() {
    echo --disable-libfreetype
}
