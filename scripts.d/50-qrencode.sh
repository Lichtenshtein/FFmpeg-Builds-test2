#!/bin/bash

SCRIPT_REPO="https://github.com/GerHobbelt/libqrencode.git"
SCRIPT_COMMIT="21c31742474699306cafb64ca2e7b293cd96c57d"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    autoreconf -if

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --disable-shared
        --enable-static
        --without-tools
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
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-libqrencode
}

ffbuild_unconfigure() {
    echo --disable-libqrencode
}
