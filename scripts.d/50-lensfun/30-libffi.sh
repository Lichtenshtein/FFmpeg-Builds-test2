#!/bin/bash
SCRIPT_REPO="https://github.com/libffi/libffi.git"
SCRIPT_COMMIT="v3.4.6"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    ./autogen.sh
    ./configure \
        --prefix="$FFBUILD_PREFIX" \
        --host="$FFBUILD_TOOLCHAIN" \
        --enable-static \
        --disable-shared \
        --with-pic
    make -j$(nproc) V=1
    make install DESTDIR="$FFBUILD_DESTDIR"
}
