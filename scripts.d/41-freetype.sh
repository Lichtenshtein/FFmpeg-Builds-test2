#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/freetype/freetype.git"
SCRIPT_COMMIT="25a08f24cfc0da879d1938352d026532f280b77e"

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
    echo "rm -rf docs/oldlogs"
}

ffbuild_dockerbuild() {
    set -e

    if has_library "icudt"; then
        log_info "ICU library detected."
        local ICU_H_LIBS="-lharfbuzz-icu"
    fi

    local DEP_LIBS="${ICU_H_LIBS} -lharfbuzz-subset -lharfbuzz-cairo -lcairo-gobject -lcairo -lharfbuzz-vector -lharfbuzz-raster -lharfbuzz -lpng -lbz2 -lbrotlienc -lbrotlidec -lbrotlicommon -lz"
    local WIN_LIBS="$LIBS"

    ./autogen.sh

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

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DFT2_BUILD_LIBRARY"

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    CFLAGS="$CFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    CPPFLAGS="$CPPFLAGS $static_flags" \
    CXXFLAGS="$CXXFLAGS $static_flags ${USELTO}${USELTO_C}" \
    LIBS="$DEP_LIBS $WIN_LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    for pc in "$PC_DIR"/{freetype,freetype2}.pc; do
        [[ -f "$pc" ]] || continue
        sed -i "s|^Cflags:.*|Cflags: -I\${includedir}/freetype2|" "$pc"
    done
    local PC_LINK="$PC_DIR/freetype.pc"
    ln -sf freetype2.pc "$PC_LINK"
}

ffbuild_configure() {
    echo --enable-libfreetype
}

ffbuild_unconfigure() {
    echo --disable-libfreetype
}