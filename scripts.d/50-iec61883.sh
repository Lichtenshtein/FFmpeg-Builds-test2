#!/bin/bash

SCRIPT_REPO="https://git.kernel.org/pub/scm/libs/ieee1394/libiec61883.git"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    git clone --depth=1 https://git.kernel.org/pub/scm/libs/ieee1394/libraw1394.git
    cd libraw1394
    autoreconf -if
    ./configure "${myconf[@]}"
    make -j$(nproc)
    make install
    cd ..

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
    echo --enable-libiec61883
}

ffbuild_unconfigure() {
    echo --disable-libiec61883
}
