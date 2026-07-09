#!/bin/bash

SCRIPT_REPO="https://github.com/harfbuzz/harfbuzz.git"
SCRIPT_COMMIT="8647a429cecb43c6e9ecb6c5bd912d33aaec03bf"

ffbuild_depends() {
    echo freetype
    echo libicu
    echo glib2
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

    mkdir build && cd build

    local myconf=(
        --cross-file="$FFBUILD_MESON_CROSS"
        --prefix="$FFBUILD_PREFIX"
        --libdir=lib
        --buildtype=release
        --default-library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        -Dcpp_std=gnu++20
        -Dc_std=gnu17
        -Draster=enabled
        -Dvector=enabled
        -Dsubset=enabled
        -Dgobject=enabled
        -Dcairo=disabled
        -Dchafa=disabled
        -Dtests=disabled
        -Dintrospection=disabled
        -Ddocs=disabled
        -Ddoc_tests=false
        -Dutilities=disabled
        -Ddirectwrite=enabled
        -Dgdi=enabled
        -Dbenchmark=disabled
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( -Db_lto=true )

    local FREETYPE_LIBS=""
    local GLIB_LIBS=""
    local ICU_LIBS=""

    export static_flags=""
    export self_static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && self_static_flags="-DHARFBUZZ_STATIC"

    if has_library "freetype"; then
        log_info "Freetype library detected. Building Harfbuzz with Freetype support..."
        myconf+=( -Dfreetype=enabled )
        local FREETYPE_LIBS="-lfreetype"
        local FT_C_FLAGS="-I$FFBUILD_PREFIX/include/freetype2"
    else
        log_warn "Freetype library not found. Building Harfbuzz without Freetype..."
        myconf+=( -Dfreetype=disabled )
    fi
    if has_library "glib-2.0"; then
        log_info "GLib2 library detected. Building Harfbuzz with GLib support..."
        myconf+=( -Dglib=enabled )
        local GLIB_LIBS="-lgio-2.0 -lgthread-2.0 -lglib-2.0"
    else
        log_warn "GLib2 library not found. Building Harfbuzz without GLib..."
        myconf+=( -Dglib=disabled )
    fi
    if has_library "icudt"; then
        log_info "ICU library detected. Building Harfbuzz with ICU support..."
        myconf+=( -Dicu=enabled )
        local ICU_LIBS="-licuin -licuuc -licudt"
        [[ "${PREFER_SHARED}" != "1" ]] && static_flags="$static_flags -DICU_STATIC -DU_STATIC_IMPLEMENTATION"
    else
        log_warn "ICU library not found. Building Harfbuzz without ICU..."
        myconf+=( -Dicu=disabled )
    fi

    local DEP_LIBS="-Wl,--start-group ${GLIB_LIBS} ${FREETYPE_LIBS} ${ICU_LIBS} -lz -Wl,--end-group"

    local WIN_LIBS="-lusp10 -lgdi32 -lrpcrt4 $LIBS"

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} ${FT_C_FLAGS} $self_static_flags $static_flags -Wno-redundant-decls" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} ${FT_C_FLAGS} $self_static_flags $static_flags -Wno-redundant-decls" \
        -Dc_link_args="$LDFLAGS ${USELTO}${USELTO_L} $DEP_LIBS $WIN_LIBS" \
        -Dcpp_link_args="$LDFLAGS ${USELTO}${USELTO_L} $DEP_LIBS $WIN_LIBS" || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    if ls "$PC_DIR"/*harfbuzz*.pc >/dev/null 2>&1; then
        for pc in "$PC_DIR"/*harfbuzz*.pc; do
            [[ -e "$pc" ]] || continue
            if [[ -n "$static_flags" ]]; then
                if ! grep -qF -- "$static_flags" "$pc"; then
                    sed -i "/^Cflags:/ s/$/ $self_static_flags $static_flags/" "$pc"
                fi
            fi
        done
    fi
}
