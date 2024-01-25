#!/bin/bash

SCRIPT_REPO="https://svn.code.sf.net/p/xavs/code/trunk"
SCRIPT_REV="55"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "retry-tool sh -c \"rm -rf xavs && svn checkout '${SCRIPT_REPO}@${SCRIPT_REV}' xavs\" && cd xavs"
}

ffbuild_dockerbuild() {

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --enable-pic
    )

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
            --cross-prefix="$FFBUILD_CROSS_PREFIX"
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
    echo --enable-libxavs
}

ffbuild_unconfigure() {
    echo --disable-libxavs
}
