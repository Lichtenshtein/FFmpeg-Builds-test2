#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/freetype/freetype.git"
SCRIPT_COMMIT="5336c0d4da22a13dab3389eb153b12672fdf841c"

ffbuild_depends() {
    echo zlib
    echo bzlib
    echo brotli
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

    if [[ -f "subprojects/dlg/meson_options.txt" ]]; then
        log_info "Patching subprojects/dlg to always use color..."
        sed -i "s/option('default_output_always_color', type: 'boolean', value: false)/option('default_output_always_color', type: 'boolean', value: true)/" subprojects/dlg/meson_options.txt
    fi

    mkdir build && cd build

    local myconf=(
        --cross-file="$FFBUILD_MESON_CROSS"
        --prefix="$FFBUILD_PREFIX"
        --libdir=lib
        --buildtype=release
        --default-library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        -Dcpp_std=gnu++20
        -Dc_std=gnu17
        -Dharfbuzz=auto
        -Dpng=auto
        -Dzlib=external
        -Dbzip2=auto
        -Dbrotli=auto
        -Dtests=disabled
        -Dmmap=auto
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( -Db_lto=true )

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DFT2_BUILD_LIBRARY"

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags" \
        -Dc_link_args="$LDFLAGS ${USELTO}${USELTO_L} $LIBS" \
        -Dcpp_link_args="$LDFLAGS ${USELTO}${USELTO_L} $LIBS" || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    for pc in "$PC_DIR"/{freetype,freetype2}.pc; do
        [[ -f "$pc" ]] || continue
        sed -i "s|^Cflags:.*|Cflags: -I\${includedir}/freetype2 $static_flags|" "$pc"
    done

    local PC_LINK="$PC_DIR/freetype.pc"
    ln -sf freetype2.pc "$PC_LINK"
}
