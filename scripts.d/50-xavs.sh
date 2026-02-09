#!/bin/bash

SCRIPT_REPO="https://svn.code.sf.net/p/xavs/code/trunk"
SCRIPT_REV="55"

ffbuild_enabled() {
    [[ $TARGET == *arm64 ]] && return -1
    return 0
}

# ffbuild_dockerdl() {
    # echo "retry-tool sh -c \"rm -rf xavs && svn checkout '${SCRIPT_REPO}@${SCRIPT_REV}' xavs\" && cd xavs"
# }

ffbuild_dockerdl() {
    echo "retry-tool svn checkout '${SCRIPT_REPO}@${SCRIPT_REV}' ."
}

ffbuild_dockerbuild() {
    if [[ -d "/builder/patches/xavs" ]]; then
        for patch in /builder/patches/xavs/*.patch; do
            echo "Applying $patch"
            patch -p1 < "$patch"
        done
    fi

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
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-libxavs
}

ffbuild_unconfigure() {
    echo --disable-libxavs
}
