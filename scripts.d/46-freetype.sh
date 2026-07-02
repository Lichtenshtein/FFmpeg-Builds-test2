#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/freetype/freetype.git"
SCRIPT_COMMIT="25a08f24cfc0da879d1938352d026532f280b77e"

ffbuild_depends() {
    echo brotli
    echo bzlib
    echo harfbuzz
    echo libpng
    echo librsvg
    echo zlib
    echo fontconfig
}

ffbuild_enabled() {
    # SVG support via librsvg is by default only for demo programs (FT_DEMO_LDFLAGS), not for the library itself
    return 1
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

    ./autogen.sh

    local DEP_LIBS="-Wl,--start-group -lrsvg_2 ${ICU_H_LIBS} -lharfbuzz-subset -lharfbuzz-cairo -lcairo-gobject -lcairo -lharfbuzz-vector -lharfbuzz-raster -lharfbuzz -lpng -lbz2 -lbrotlienc -lbrotlidec -lbrotlicommon -lz -Wl,--end-group"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --with-harfbuzz
        --with-png
        --with-zlib
        --with-bzip2
        --with-brotli
        --with-librsvg # for demo programs (FT_DEMO_LDFLAGS)
        --with-pic
    )

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DFT2_BUILD_LIBRARY"
    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    CFLAGS="$CFLAGS ${USELTO}${USELTO_C}" \
    CPPFLAGS="$CPPFLAGS $static_flags" \
    CXXFLAGS="$CXXFLAGS $static_flags ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    LIBS="$DEP_LIBS $LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    for pc in "$PC_DIR"/{freetype,freetype2}.pc; do
        [[ -f "$pc" ]] || continue
        # Убеждаемся, что Cflags указывает на правильную подпапку
        sed -i "s|^Cflags:.*|Cflags: -I\${includedir}/freetype2|" "$pc"
    done
    # Создаем симлинк
    local PC_LINK="$PC_DIR/freetype.pc"
    ln -sf freetype2.pc "$PC_LINK"
}

ffbuild_configure() {
    echo --enable-libfreetype
}

ffbuild_unconfigure() {
    echo --disable-libfreetype
}
