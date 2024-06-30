#!/bin/bash

SCRIPT_REPO="https://github.com/dlbeer/quirc"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {

    for patch in /patches/*.patch; do
        echo "Applying $patch"
        patch -p1 < "$patch"
    done

    export CC="$CC"
    export CFLAGS="$CFLAGS"

    make libquirc.a -j$(nproc)
    cp libquirc.a "$FFBUILD_PREFIX/lib/"
}

ffbuild_configure() {
    echo --enable-libquirc
}

ffbuild_unconfigure() {
    echo --disable-libquirc
}

ffbuild_cflags() {
    return 0
}

ffbuild_ldflags() {
    return 0
}
