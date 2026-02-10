#!/bin/bash

#SCRIPT_REPO="https://github.com/Konstanty/libmodplug"

SCRIPT_REPO="https://github.com/mywave82/libmodplug.git"
SCRIPT_COMMIT="dadf7058372c04ab28ee1fb5475d05e5e191e72e"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
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
    make -j$(nproc) V=1
    make install DESTDIR="$FFBUILD_DESTDIR"
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