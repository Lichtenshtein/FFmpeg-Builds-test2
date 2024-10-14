#!/bin/bash

SCRIPT_REPO="https://github.com/Konstanty/libmodplug"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    autoreconf -if

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --disable-shared
        --enable-static
        --with-pic
    )

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
        )
    else
        echo "Unknown target"
        return -1
    fi

    ./configure "${myconf[@]}"
    make -j$(nproc)
    make install
}

ffbuild_configure() {
    echo --enable-libmodplug
}

ffbuild_unconfigure() {
    echo --disable-libmodplug
}

ffbuild_cflags() {
    echo -DMODPLUG_STATIC
}