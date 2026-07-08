#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/cairo/cairo.git"
SCRIPT_COMMIT="8e3ac5e404f45b92ea186ad7a776b5e5160f38ac"

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
    echo "rm -rf test perf"
}

ffbuild_dockerbuild() {
    set -e

    # fix error: implicit declaration of function '_hypot'
    sed -i 's/#define hypot _hypot/\/\/#define hypot _hypot/' src/cairo-compiler-private.h

    # Remove gnu_symbol_visibility from all meson.builds
    # if [ -f "src/cairo.h" ]; then
        # sed -i 's/# define _cairo_export __attribute__((__visibility__("default")))/# define _cairo_export/g' src/cairo.h
    # fi
    # if [ -f "src/cairo-compiler-private.h" ]; then
        # sed -i 's/#define CAIRO_HAS_HIDDEN_SYMBOLS 1/#define CAIRO_HAS_HIDDEN_SYMBOLS 0/g' src/cairo-compiler-private.h
        # sed -i 's/#define cairo_private_no_warn.*/#define cairo_private_no_warn/g' src/cairo-compiler-private.h
    # fi

    if [ -f "util/cairo-script/cairo-script-private.h" ]; then
        sed -i 's/#define csi_private_no_warn.*/#define csi_private_no_warn/g' util/cairo-script/cairo-script-private.h
    fi

    mkdir -p _build && cd _build

    [[ "${TARGET}" == "win64" ]] && export LDFLAGS=$(echo "$LDFLAGS" | sed 's/-lrt//g')

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --cross-file="$FFBUILD_MESON_CROSS"
        --buildtype=release
        --default-library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        --wrap-mode=nodownload
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false)
        -Dcpp_std=gnu++20
        -Dspectre=disabled
        -Dgtk_doc=false
        -Dsymbol-lookup=disabled
        -Dtee=enabled
        -Dtests=disabled
        -Dxcb=disabled
        -Dxlib=$([ "${TARGET}" == "linux64" ] && echo enabled || echo disabled)
    )

    if has_library "z"; then
        log_info "ZLIB library detected. Building with ZLIB support..."
        myconf+=(
            -Dzlib=enabled
        )
        local Z_LIB="-lz"
    fi
    if has_library "glib-2.0"; then
        log_info "Glib2 library detected. Building with Glib2 support..."
        myconf+=(
            -Dglib=enabled
        )
        local GLIB2_LIB="-lgio-2.0 -lgthread-2.0 -lglib-2.0"
    fi
    if has_library "png"; then
        log_info "PNG library detected. Building with PNG support..."
        myconf+=(
            -Dpng=enabled
        )
        local PNG_LIB="-lpng"
    fi
    if has_library "freetype"; then
        log_info "Freetype library detected. Building with Freetype support..."
        myconf+=(
            -Dfreetype=enabled
        )
        local FREETYPE_LIBS="-lfreetype"
    fi
    if has_library "fontconfig"; then
        log_info "Fontconfig library detected. Building with Fontconfig support..."
        myconf+=(
            -Dfontconfig=enabled
        )
        local FONTCONF_LIBS="-lfontconfig"
    fi
    if has_library "icudt"; then
        log_info "ICU library detected."
        local ICU_LIBS="-licuin -licuuc -licudt"
    fi

    local DEP_LIBS="-Wl,--start-group ${FONTCONF_LIBS} -lpixman-1 -lxml2 ${PNG_LIB} ${GLIB2_LIB} ${FREETYPE_LIBS} -lbz2 -lbrotlienc -lbrotlidec -lbrotlicommon ${Z_LIB} -lintl -liconv -lcharset ${ICU_LIBS} -Wl,--end-group"
    local WIN_LIBS="-lgdi32 -lmsimg32 -ldwrite -ld2d1 -lwindowscodecs -lopengl32 -luuid $LIBS -lstdc++"

    export static_flags=""
    export self_static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-Dpixman_static" && self_static_flags="-DCAIRO_WIN32_STATIC_BUILD"

    meson setup . .. \
        "${myconf[@]}" \
        -Dc_args="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags $self_static_flags" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags $self_static_flags" \
        -Dc_link_args="$LDFLAGS ${USELTO}${USELTO_L} $DEP_LIBS $WIN_LIBS" \
        -Dcpp_link_args="$LDFLAGS ${USELTO}${USELTO_L} $DEP_LIBS $WIN_LIBS" || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    mkdir -p "$PC_DIR"
    if [ -d "$PC_DIR" ]; then
        find "$PC_DIR" -name "*.pc" | while read -r PC_FILE; do
            sed -i "s/-lrt//g" "$PC_FILE"
            sed -i "s|^Cflags:.*|& -I\${includedir}/cairo|" "$PC_FILE"
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