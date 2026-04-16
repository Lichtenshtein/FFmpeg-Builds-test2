#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/xorg/lib/libpciaccess.git"
SCRIPT_COMMIT="30cfe2325d816991610a8224a49cfa12317d7f67"

ffbuild_depends() {
    echo base
    echo zlib
}

ffbuild_enabled() {
    [[ $TARGET != linux* ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build && cd build

    local myconf=(
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false )
        --prefix="$FFBUILD_PREFIX"
        --buildtype=release
        --default-library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        -Dcpp_std=c++17
        -Dc_std=c11
        -Dzlib=enabled
    )

    if [[ $TARGET == linux* ]]; then
        myconf+=(
            --cross-file="$FFBUILD_MESON_CROSS"
        )
    fi

    meson setup "${myconf[@]}" .. \
        -Dc_args="$RAW_CFLAGS $CPPFLAGS" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS" \
        -Dc_link_args="$RAW_LDFLAGS" \
        -Dcpp_link_args="$RAW_LDFLAGS" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    gen-implib "$FFBUILD_DESTPREFIX"/lib/{libpciaccess.so.0,libpciaccess.a}
    rm "$FFBUILD_DESTPREFIX"/lib/libpciaccess.so*

    echo "Libs: -ldl" >> "$PC_DIR/pciaccess.pc"
}
