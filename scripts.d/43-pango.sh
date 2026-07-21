#!/bin/bash

SCRIPT_REPO="https://gitlab.gnome.org/GNOME/pango.git"
SCRIPT_COMMIT="2b3ad511996d75b8d26bc0fae4f75374dfce9ffa"

ffbuild_depends() {
    echo fontconfig
    echo freetype
    echo glib2
    echo cairo
    echo fribidi
    echo harfbuzz
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-submodule-clone"
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build && cd build

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --cross-file="$FFBUILD_MESON_CROSS"
        --buildtype=release
        --default-library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        --wrap-mode=nodownload
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false)
        -Dcpp_std=gnu++20
        -Dc_std=gnu17
        -Dintrospection=disabled
        -Dsysprof=disabled
        -Ddocumentation=false
        -Dbuild-testsuite=false
        -Dbuild-examples=false
        -Dman-pages=false
    )

    if has_library "freetype"; then
        log_info "Freetype library detected. Building with Freetype support..."
        myconf+=( -Dfreetype=enabled )
        local FREETYPE_LIBS="-lfreetype"
    fi
    if has_library "fontconfig"; then
        log_info "Fontconfig library detected. Building with Fontconfig support..."
        myconf+=( -Dfontconfig=enabled )
        local FONTCONF_LIBS="-lfontconfig"
    fi
    if has_library "icudt"; then
        log_info "ICU library detected."
        local ICU_LIBS="-licuin -licuuc -licudt"
        local ICU_H_LIBS="-lharfbuzz-icu"
    fi

    local DEP_LIBS="-Wl,--start-group ${ICU_H_LIBS} -lharfbuzz-subset -lharfbuzz-cairo -lharfbuzz-vector -lharfbuzz-raster -lharfbuzz -lcairo-gobject -lcairo ${FONTCONF_LIBS} ${FREETYPE_LIBS} -lgio-2.0 -lgthread-2.0 -lglib-2.0 -lfribidi -lbz2 -lbrotlienc -lbrotlidec -lbrotlicommon -lz -lintl -liconv -lcharset ${ICU_LIBS} -Wl,--end-group"
    local WIN_LIBS="-lrpcrt4 -lusp10 -lgdi32 -lmsimg32 -lruntimeobject -ldwrite -ld2d1 -lwindowscodecs -luuid $LIBS -lstdc++"
    local LDFLAGS=$(echo "$LDFLAGS" | sed 's/-lssp//g')

    export static_flags=""
    export self_static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DCAIRO_WIN32_STATIC_BUILD -DPANGO_STATIC_COMPILATION -DG_WIN32_IS_STRICT_MINGW -Dpixman_static" && self_static_flags="-DPANGO_STATIC_COMPILATION"

    sed -i "s/error.*does not have the required FontConfig support.*/message('Bypassed cairo-ft check')/" ../meson.build

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags $self_static_flags" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags $self_static_flags" \
        -Dc_link_args="$LDFLAGS ${USELTO}${USELTO_L} $DEP_LIBS $WIN_LIBS" \
        -Dcpp_link_args="$LDFLAGS ${USELTO}${USELTO_L} $DEP_LIBS $WIN_LIBS" || return 1

    if [[ "${PREFER_SHARED}" == "1" ]]; then
        ninja $NINJA_V || return 1
        DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1
    else
        # only compile libraries (because building exes crashes with LTO)
        ninja pango/libpango-1.0.a \
              pango/libpangocairo-1.0.a \
              pango/libpangoft2-1.0.a \
              pango/libpangowin32-1.0.a || return 1

        mkdir -p "$PC_DIR" "$INSTALL_ROOT/include/pango-1.0/pango"
        cp pango/*.a "$INSTALL_ROOT/lib/"
        cp ../pango/*.h "$INSTALL_ROOT/include/pango-1.0/pango/" 2>/dev/null || true
        cp pango/*.h "$INSTALL_ROOT/include/pango-1.0/pango/" 2>/dev/null || true
        cp meson-private/*pango*.pc "$PC_DIR/"
    fi

    for pc in "$PC_DIR"/*pango*.pc; do
        [[ -e "$pc" ]] || continue
        if [[ -n "$self_static_flags" ]]; then
            if ! grep -qF -- "$self_static_flags" "$pc"; then
                sed -i "/^Cflags:/ s/$/ $self_static_flags/" "$pc"
            fi
        fi
    done
}
