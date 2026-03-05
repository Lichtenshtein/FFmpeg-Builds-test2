#!/bin/bash

SCRIPT_REPO="https://github.com/mccakit/fdk-aac.git"
SCRIPT_COMMIT="61d2f80c677a1b0d75214f27edd48dedf24528e9"

ffbuild_enabled() {
    # [[ $VARIANT == nonfree* ]] || return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    apply_patches

    ./autogen.sh

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-shared
        --enable-static
        --with-pic
        --disable-example
    )

    local flags="-fsanitize=address,undefined -fno-omit-frame-pointer -fno-sanitize=shift-base -fno-sanitize-recover=all"
    
    export CC="gcc $flags"
    export CXX="g++ $flags"

    ./configure "${myconf[@]}"
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    clean_la_files

    get_deps_list
}

ffbuild_configure() {
    echo --enable-libfdk-aac
}

ffbuild_unconfigure() {
    echo --disable-libfdk-aac
}
