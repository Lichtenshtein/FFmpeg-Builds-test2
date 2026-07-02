#!/bin/bash

SCRIPT_REPO="https://github.com/harfbuzz/harfbuzz.git"
SCRIPT_COMMIT="8647a429cecb43c6e9ecb6c5bd912d33aaec03bf"

ffbuild_depends() {
    echo freetype
    echo libicu
    echo glib2
    echo cairo
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

    mkdir -p build && cd build

    local myconf=(
        --cross-file="$FFBUILD_MESON_CROSS"
        --prefix="$FFBUILD_PREFIX"
        --libdir=lib
        --buildtype=release
        --default-library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false)
        -Dfreetype=enabled
        -Dcpp_std=gnu++20
        -Dc_std=gnu17
        -Dwith_libstdcxx=true
        -Draster=enabled
        -Dvector=enabled
        -Dsubset=enabled
        -Dglib=enabled
        -Dgobject=disabled
        -Dcairo=enabled
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

    # Проверяем наличие библиотеки libicudt
    if has_library "icudt"; then
        log_info "ICU library detected. Building with ICU support..."
        local DEP_LIBS="-lcairo-gobject -lcairo -lgio-2.0 -lgthread-2.0 -lglib-2.0 -lz -lfreetype -licuin -licuuc -licudt"
        myconf+=( "-Dicu=enabled" )
    else
        log_warn "ICU library not found. Building without ICU for faster testing..."
        local DEP_LIBS="-lcairo-gobject -lcairo -lgio-2.0 -lgthread-2.0 -lglib-2.0 -lz -lfreetype"
        myconf+=( "-Dicu=disabled" )
    fi

    export static_flags=""
    export self_static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DCAIRO_WIN32_STATIC_BUILD -DICU_STATIC -DU_STATIC_IMPLEMENTATION" && self_static_flags="-DHARFBUZZ_STATIC"

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -I$FFBUILD_PREFIX/include/freetype2 $self_static_flags $static_flags -Wno-redundant-decls" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -I$FFBUILD_PREFIX/include/freetype2 $self_static_flags $static_flags -Wno-redundant-decls" \
        -Dc_link_args="$LDFLAGS ${USELTO}${USELTO_L} $DEP_LIBS $WIN_LIBS" \
        -Dcpp_link_args="$LDFLAGS ${USELTO}${USELTO_L} $DEP_LIBS $WIN_LIBS" || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    if ls "$PC_DIR"/*harfbuzz*.pc >/dev/null 2>&1; then
        for pc in "$PC_DIR"/*harfbuzz*.pc; do
            [[ -e "$pc" ]] || continue
            if [[ -n "$self_static_flags" ]]; then
                if ! grep -qF -- "$self_static_flags" "$pc"; then
                    sed -i "/^Cflags:/ s/$/ $self_static_flags/" "$pc"
                fi
            fi
        done
    fi
}

ffbuild_cppflags() {
    echo "$self_static_flags"
}

ffbuild_configure() {
    echo --enable-libharfbuzz
}

ffbuild_unconfigure() {
    echo --disable-libharfbuzz
}
