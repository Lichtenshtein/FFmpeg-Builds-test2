#!/bin/bash

SCRIPT_REPO="https://github.com/harfbuzz/harfbuzz.git"
SCRIPT_COMMIT="3db272507d23e2335bdd2c30903f466452edd344"

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
}

ffbuild_dockerbuild() {
    set -e

    mkdir build && cd build

    local DEP_LIBS="-lfreetype -lsicuin -lsicuuc -lsicudt"
    local WIN_LIBS="-lusp10 -lgdi32 -lrpcrt4 $LIBS"

    local myconf=(
        --cross-file="$FFBUILD_MESON_CROSS"
        --prefix="$FFBUILD_PREFIX"
        --libdir=lib
        --buildtype=release
        --default-library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        -Dcpp_std=c++17
        -Dc_std=c11
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

    [[ "$USE_LTO" == "1" ]] && myconf+=( -Db_lto=true )

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DHARFBUZZ_STATIC"

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -I$FFBUILD_PREFIX/include/freetype2 $static_flags -Wno-redundant-decls" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -I$FFBUILD_PREFIX/include/freetype2 $static_flags -Wno-redundant-decls" \
        -Dc_link_args="$LDFLAGS ${USELTO} $DEP_LIBS $WIN_LIBS" \
        -Dcpp_link_args="$LDFLAGS ${USELTO} $DEP_LIBS $WIN_LIBS" || return 1

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
