#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/freetype/freetype.git"
SCRIPT_COMMIT="67c52a0b68eaeb7ae1f2248202924883c4a232d0"

ffbuild_depends() {
    echo fontconfig
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

    local DEP_LIBS="-lharfbuzz-icu -lharfbuzz-subset -lharfbuzz-cairo -lcairo-gobject -lcairo -lharfbuzz-vector -lharfbuzz-raster -lharfbuzz -lpng16 -lbz2 -lbrotlienc -lbrotlidec -lbrotlicommon -lz"
    local WIN_LIBS="$LIBS"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --with-harfbuzz
        --with-png
        --with-zlib
        --with-bzip2
        --with-brotli
        --with-pic
    )

    local static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DFT2_BUILD_LIBRARY"

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    CFLAGS="$CFLAGS ${USELTO}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    CPPFLAGS="$CPPFLAGS $static_flags" \
    CXXFLAGS="$CXXFLAGS $static_flags ${USELTO}" \
    LIBS="$DEP_LIBS $WIN_LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    # Создаем симлинк
    local PC_LINK="$PC_DIR/freetype.pc"
    ln -sf freetype2.pc "$PC_LINK"
}