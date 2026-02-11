#!/bin/bash

SCRIPT_REPO="https://github.com/njh/twolame.git"
SCRIPT_COMMIT="3c7d49d95be71c26afdbaef14def92f3460c7373"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
}

ffbuild_dockerbuild() {

    NOCONFIGURE=1 ./autogen.sh
    touch doc/twolame.1

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --with-pic
        --disable-shared
        --enable-static
        --disable-sndfile
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
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    sed -i 's/Cflags:/Cflags: -DLIBTWOLAME_STATIC/' "$FFBUILD_DESTPREFIX"/lib/pkgconfig/twolame.pc
}

ffbuild_configure() {
    echo --enable-libtwolame
}

ffbuild_unconfigure() {
    echo --disable-libtwolame
}

ffbuild_cflags() {
    echo -DLIBTWOLAME_STATIC
}
