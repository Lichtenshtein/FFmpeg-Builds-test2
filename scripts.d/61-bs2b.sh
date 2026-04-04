#!/bin/bash

SCRIPT_REPO="https://github.com/insilications/libbs2b-clr.git"
SCRIPT_COMMIT="6124876cba8585b814a81f15e0019d04127162da"

# SCRIPT_REPO="https://github.com/alexmarsev/libbs2b.git"
# SCRIPT_COMMIT="5ca2d59888df047f1e4b028e3a2fd5be8b5a7277"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
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
        return 1
    fi

    CFLAGS="$CFLAGS" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS" \
    LDFLAGS="$LDFLAGS" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

}

ffbuild_configure() {
    echo --enable-libbs2b
}

ffbuild_unconfigure() {
    echo --disable-libbs2b
}
