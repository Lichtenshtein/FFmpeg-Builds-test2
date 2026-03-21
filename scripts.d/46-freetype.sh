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
        CXXFLAGS="$CXXFLAGS -DFT2_BUILD_LIBRARY" \
        LIBS="$DEP_LIBS" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    clean_la_files

    local PC_DIR="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig"
    log_info "${SYNC_MARK} Patching FREETYPE .pc files..."
    for pc in "$PC_DIR"/freetype2.pc; do
        [[ -e "$pc" ]] || continue
        if ! grep -q "DFT2_BUILD_LIBRARY" "$pc"; then
            sed -i '/^Cflags:/ s/$/ -DFT2_BUILD_LIBRARY/' "$pc"
        fi
        if grep -q "^Libs.private:" "$pc"; then
            sed -i "s|^Libs.private:.*|Libs.private: $DEP_LIBS|" "$pc"
        else
            sed -i "/^Libs:/ a Libs.private: $DEP_LIBS" "$pc"
        fi
    done

    # Создаем симлинк
    ln -sf freetype2.pc "$PC_LINK"

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
