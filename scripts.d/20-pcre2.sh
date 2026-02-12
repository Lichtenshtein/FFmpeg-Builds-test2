#!/bin/bash

SCRIPT_REPO="https://github.com/PCRE2Project/pcre2.git"
SCRIPT_COMMIT="pcre2-10.42"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    ./autogen.sh

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --enable-static
        --disable-shared
        --enable-pcre2-8
        --enable-pcre2-16
        --enable-pcre2-32
        --enable-jit
        --disable-stack-for-recursion
    )

    ./configure "${myconf[@]}"

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"
}
