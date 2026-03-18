#!/bin/bash

SCRIPT_REPO="https://github.com/drobilla/serd.git"
SCRIPT_COMMIT="1fd12ee91b4dfc124ce4435b1fe52b3a69c75255"

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
        -Dtools=disabled
        -Dtests=disabled
    )

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --cross-file=/cross.meson
        )
    else
        echo "Unknown target"
        return 1
    fi

    meson "${myconf[@]}" .. || return 1
    ninja -j"$(nproc)" $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    get_deps_list
}
