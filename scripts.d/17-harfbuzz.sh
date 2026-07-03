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
        -Db_lundef=false
        --cross-file="$FFBUILD_MESON_CROSS"
        --prefix="$FFBUILD_PREFIX"
        --libdir=lib
        --buildtype=release
        --default-library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        -Dcpp_std=gnu++20
        -Dc_std=gnu17
        -Dfreetype=enabled
        -Draster=enabled
        -Dvector=enabled
        -Dsubset=enabled
        -Dglib=enabled
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

    local WIN_LIBS="-lusp10 -lgdi32 -lrpcrt4 $LIBS"

    # проверяем наличие библиотеки libicudt
    if has_library "icudt"; then
        log_info "ICU library detected. Building with ICU support..."
        local DEP_LIBS="-lfreetype -licuin -licuuc -licudt"
        myconf+=( "-Dicu=enabled" )
    else
        log_warn "ICU library not found. Building without ICU for faster testing..."
        local DEP_LIBS="-lfreetype"
        myconf+=( "-Dicu=disabled" )
    fi

    [[ "$USE_LTO" == "1" ]] && myconf+=( -Db_lto=true )

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DHARFBUZZ_STATIC -DICU_STATIC -DU_STATIC_IMPLEMENTATION"

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -I$FFBUILD_PREFIX/include/freetype2 $static_flags -Wno-redundant-decls" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -I$FFBUILD_PREFIX/include/freetype2 $static_flags -Wno-redundant-decls" \
        -Dc_link_args="$LDFLAGS ${USELTO}${USELTO_L} $DEP_LIBS $WIN_LIBS" \
        -Dcpp_link_args="$LDFLAGS ${USELTO}${USELTO_L} $DEP_LIBS $WIN_LIBS" || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    if ls "$PC_DIR"/*harfbuzz*.pc >/dev/null 2>&1; then
        for pc in "$PC_DIR"/*harfbuzz*.pc; do
            [[ -e "$pc" ]] || continue
            if [[ -n "$static_flags" ]]; then
                if ! grep -qF -- "$static_flags" "$pc"; then
                    sed -i "/^Cflags:/ s/$/ $static_flags/" "$pc"
                fi
            fi
        done
    fi
}
