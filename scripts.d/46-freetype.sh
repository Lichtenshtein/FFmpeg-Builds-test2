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

    local DEP_LIBS="-lrsvg-2 -lfontconfig -lharfbuzz-cairo -lcairo -lharfbuzz-subset -lharfbuzz-vector -lharfbuzz-raster -lharfbuzz -lharfbuzz-icu -lpng16 -lbz2 -lbrotlidec -lbrotlicommon -lz -lsicuin -lsicuuc -lsicudt $LIBS"

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

    ./configure "${myconf[@]}" \
        CFLAGS="$CFLAGS -DFT2_BUILD_LIBRARY" \
        LDFLAGS="$LDFLAGS" \
        CPPFLAGS="$CPPFLAGS -DFT2_BUILD_LIBRARY" \
        CXXFLAGS="$CXXFLAGS -DFT2_BUILD_LIBRARY" || return 1
    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    clean_la_files

    # Создаем симлинк для совместимости
    ln -sf freetype2.pc "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/freetype.pc"

    for pc in "$FFBUILD_DESTDIR$FFBUILD_PREFIX"/lib/pkgconfig/freetype2.pc; do
        [[ -e "$pc" ]] || continue
        log_info "${SYNC_MARK} Patching FREETYPE .pc file..."
        if ! grep -q "\-DFT2_BUILD_LIBRARY" "$PC_FILE"; then
            sed -i 's/Cflags:/& -DFT2_BUILD_LIBRARY/' "$PC_FILE"
        fi
        sed -i "s|^Libs.private:.*|Libs.private: $DEP_LIBS|" "$PC_FILE"
    done

    get_deps_list
}

ffbuild_cppflags() {
    echo "-DFT2_BUILD_LIBRARY"
}

ffbuild_configure() {
    echo --enable-libfreetype
}

ffbuild_unconfigure() {
    echo --disable-libfreetype
}
