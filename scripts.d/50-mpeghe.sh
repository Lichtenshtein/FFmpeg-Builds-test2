#!/bin/bash

SCRIPT_REPO="https://github.com/ittiam-systems/libmpeghe"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    cd encoder
    
    for mpeghe in *.c; do
        "$CC" $CFLAGS -I. "$mpeghe" -c -o "${mpeghe%.c}.o"
    done

    "$AR" rcs libia_mpegh.a *.o
    "$RANLIB" libia_mpegh.a

    cp libia_mpegh.a "$FFBUILD_PREFIX"/lib
}

ffbuild_configure() {
    echo --enable-ia_mpegh
}

ffbuild_unconfigure() {
    echo --disable-ia_mpegh
}
