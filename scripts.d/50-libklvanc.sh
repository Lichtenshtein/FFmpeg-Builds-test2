#!/bin/bash

SCRIPT_REPO="https://github.com/stoth68000/libklvanc.git"
SCRIPT_COMMIT="b409fc2b0b8051c871f89367a3489f8aa2b6ed37"

ffbuild_enabled() {
    [[ $TARGET == winarm64 ]] && return -1
    [[ $TARGET == linux* ]] && return -1
    [[ $VARIANT == nonfree* ]] || return -1
    return 0
}

ffbuild_dockerbuild() {
    autoreconf -if

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-shared
        --enable-static
    )

    ./configure "${myconf[@]}"
    make -j$(nproc)
    make install
}

ffbuild_configure() {
    echo --enable-libklvanc
}

ffbuild_unconfigure() {
    echo --disable-libklvanc
}
