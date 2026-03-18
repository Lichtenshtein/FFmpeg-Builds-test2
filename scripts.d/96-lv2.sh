#!/bin/bash

SCRIPT_REPO="https://github.com/lv2/lv2.git"
SCRIPT_COMMIT="86a8bb5d103f749017e6288dbce9bbe981ed9955"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    mkdir build && cd build

    export CFLAGS="$(echo $CFLAGS | sed 's/-std=c11//g')"
    export CXXFLAGS="$(echo $CXXFLAGS | sed 's/-std=c++17//g')"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --buildtype=release
        --default-library=static
        -Dcpp_std=c++17
        -Dc_std=c11
        -Ddocs=disabled
        -Dtests=disabled
        -Donline_docs=false
    )

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --cross-file=/cross.meson
        )
    else
        echo "Unknown target"
        return 1
    fi

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS" \
        -Dcpp_args="$CPPFLAGS" \
        -Dc_link_args="$LDFLAGS" \
        -Dcpp_link_args="$LDFLAGS" || return 1
    ninja -j"$(nproc)" $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    get_deps_list
}
