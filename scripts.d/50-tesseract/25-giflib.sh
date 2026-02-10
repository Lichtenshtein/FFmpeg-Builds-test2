#!/bin/bash

SCRIPT_REPO="https://deac-fra.dl.sourceforge.net/project/giflib/giflib-5.2.2.tar.gz"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    # giflib качается архивом, так проще
    echo "curl -L \"$SCRIPT_REPO\" | tar xz --strip-components=1"
}

ffbuild_dockerbuild() {
    # Правим Makefile для кросс-компиляции
    sed -i "s|CC      = gcc|CC      = $CC|" Makefile
    sed -i "s|AR      = ar|AR      = $AR|" Makefile
    sed -i "s|RANLIB  = ranlib|RANLIB  = $RANLIB|" Makefile

    make -j$(nproc) V=1 libgif.a
    
    # Ручная установка, так как штатный install хочет в /usr/local
    mkdir -p "$FFBUILD_DESTPREFIX"/include "$FFBUILD_DESTPREFIX"/lib
    cp gif_lib.h "$FFBUILD_DESTPREFIX"/include/
    cp libgif.a "$FFBUILD_DESTPREFIX"/lib/
}

ffbuild_configure() {
    return 0
}
