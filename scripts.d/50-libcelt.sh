#!/bin/bash

SCRIPT_REPO="https://github.com/MartinEesmaa/celt.git"
SCRIPT_COMMIT="e4dcd52ac70203b869ffff1d833d028fd926750d"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    ./autogen.sh

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --disable-shared
        --enable-static
        --disable-oggtest
        --with-ogg=no
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
    echo --enable-libcelt
}

ffbuild_unconfigure() {
    echo --disable-libcelt
}
