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
    mkdir build && cd build

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --buildtype=release
        --default-library=shared
        -Dcpp_std=c++17
        -Dc_std=c11
        -Dzlib=enabled
    )

    if [[ $TARGET == linux* ]]; then
        myconf+=(
            --cross-file=/cross.meson
        )
    else
        echo "Unknown target"
        return 1
    fi

    export CFLAGS="$RAW_CFLAGS"
    export LDFLAFS="$RAW_LDFLAGS"

    meson setup "${myconf[@]}" .. || return 1
    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    gen-implib "$FFBUILD_DESTPREFIX"/lib/{libpciaccess.so.0,libpciaccess.a}
    rm "$FFBUILD_DESTPREFIX"/lib/libpciaccess.so*

    echo "Libs: -ldl" >> "$FFBUILD_DESTPREFIX"/lib/pkgconfig/pciaccess.pc

    get_deps_list
}
