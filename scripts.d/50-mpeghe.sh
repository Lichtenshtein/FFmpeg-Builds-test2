#!/bin/bash

SCRIPT_REPO="https://github.com/ittiam-systems/libmpeghe.git"
SCRIPT_COMMIT="603275bb7647cdf8db86dbdf2291495d8fdcfa7f"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
}

ffbuild_dockerbuild() {
    cd encoder
    
    for mpeghe in *.c; do
        "$CC" -Wall -Wsequence-point $CFLAGS -I. "$mpeghe" -c -o "${mpeghe%.c}.o"
    done

    "$AR" -r libia_mpegh.a *.o
    rm -f *.o

    mkdir -p "$FFBUILD_DESTPREFIX"/lib
    cp libia_mpegh.a "$FFBUILD_DESTPREFIX"/lib
}

ffbuild_configure() {
    echo --enable-ia_mpegh
}

ffbuild_unconfigure() {
    echo --disable-ia_mpegh
}

ffbuild_libs() {
    echo -lia_mpegh
}
