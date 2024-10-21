#!/bin/bash

SCRIPT_REPO="https://gitlab.gnome.org/GNOME/librsvg"
SCRIPT_COMMIT="56057d474d428e44aff0087dea637a062b5b042a"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    ./autogen.sh
    
    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --disable-shared
        --enable-static
        --with-pic
        --disable-gtk-doc
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
    echo --enable-librsvg
}

ffbuild_unconfigure() {
    echo --disable-librsvg
}
