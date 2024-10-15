#!/bin/bash

SCRIPT_REPO="https://github.com/MartinEesmaa/libgsm"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {

    export CCFLAGS="$CFLAGS -DNeedFunctionPrototypes=1 -c -DSASR -DWAV49 -Wno-comment"
    export INSTALL_ROOT="$FFBUILD_PREFIX"
    export CC="${FFBUILD_TOOLCHAIN}-gcc"

    make libgsm -j$(nproc)
    
    mkdir -p "$FFBUILD_PREFIX/include/gsm"
    cp lib/libgsm.a "$FFBUILD_PREFIX/lib/"
    cp include/gsm/*.h "$FFBUILD_PREFIX/include/gsm"
    cp include/gsm/gsm.h "$FFBUILD_PREFIX/include/"
}

ffbuild_configure() {
    echo --enable-libgsm
}

ffbuild_unconfigure() {
    echo --disable-libgsm
}

ffbuild_cflags() {
    return 0
}

ffbuild_ldflags() {
    return 0
}