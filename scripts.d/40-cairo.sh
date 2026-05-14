#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/cairo/cairo.git"
SCRIPT_COMMIT="d3a35678a2322046f6d034001f2970ed3f54a1b7"

ffbuild_depends() {
    echo zlib
    echo glib2
    echo fontconfig
    echo freetype
    echo bzlib # freetype
    echo brotli # freetype
    echo libxml2
    echo libpng
    echo pixman
    echo harfbuzz
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    # Зависимости из чит-листа в правильном порядке линковки
    local DEP_LIBS="-Wl,--start-group -lfontconfig -lpixman-1 -lxml2 -lpng16 -lgio-2.0 -lgthread-2.0 -lglib-2.0 -lfreetype -lbz2 -lbrotlienc -lbrotlidec -lbrotlicommon -lz -lintl -liconv -lcharset -licuin -licuuc -licudt -Wl,--end-group"
    # Набор системных библиотек Windows для Cairo
    local WIN_LIBS="-lgdi32 -lmsimg32 -ldwrite -ld2d1 -lwindowscodecs -lopengl32 -luuid $LIBS -lstdc++"

    # конфликт hypot в коде Cairo для MinGW
    # error: implicit declaration of function '_hypot'
    sed -i 's/#define hypot _hypot/\/\/#define hypot _hypot/' src/cairo-compiler-private.h

    mkdir -p _build && cd _build

    export LDFLAGS=$(echo "$LDFLAGS" | sed 's/-lrt//g')

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --cross-file="$FFBUILD_MESON_CROSS"
        --buildtype=release
        --default-library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        --wrap-mode=nodownload
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false)
        -Dcpp_std=gnu++20
        -Dfontconfig=enabled
        -Dfreetype=enabled
        -Dglib=enabled
        -Dspectre=disabled
        -Dpng=enabled
        -Dsymbol-lookup=disabled
        -Dtee=enabled
        -Dtests=disabled
        -Dxcb=disabled
        -Dxlib=$([ "${TARGET}" == "linux64" ] && echo enabled || echo disabled)
        -Dzlib=enabled
    )

    export static_flags=""
    export self_static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-Dpixman_static" && self_static_flags="-DCAIRO_WIN32_STATIC_BUILD"

    meson setup . .. \
        "${myconf[@]}" \
        -Dc_args="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags $self_static_flags" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags $self_static_flags" \
        -Dc_link_args="$LDFLAGS ${USELTO} $DEP_LIBS $WIN_LIBS" \
        -Dcpp_link_args="$LDFLAGS ${USELTO} $DEP_LIBS $WIN_LIBS" || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    mkdir -p "$PC_DIR"
    if [ -d "$PC_DIR" ]; then
        find "$PC_DIR" -name "*.pc" | while read -r PC_FILE; do
            sed -i "s/-lrt//g" "$PC_FILE"
            sed -i "s|^Cflags:.*|& -I${includedir}/cairo|" "$PC_FILE"
            if [[ -n "$self_static_flags" ]]; then
                if ! grep -qF -- "$self_static_flags" "$PC_FILE"; then
                    sed -i "/^Cflags:/ s/$/ $self_static_flags/" "$PC_FILE"
                fi
            fi
        done
        log_info "Cflags paths have been updated."
    fi
}

ffbuild_cppflags() {
    echo "$self_static_flags"
}

ffbuild_libs() {
    echo "-lgdi32 -lmsimg32 -ldwrite -ld2d1 -lwindowscodecs -lopengl32 -luuid -lstdc++"
}

ffbuild_configure() {
    echo --enable-cairo
}

ffbuild_unconfigure() {
    echo --disable-cairo
}