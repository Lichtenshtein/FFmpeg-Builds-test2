#!/bin/bash

SCRIPT_REPO="https://github.com/dlbeer/quirc.git"
SCRIPT_COMMIT="927d680904dc95fdff4cd9d022eb374b438ff8f2"

ffbuild_enabled() {
    [[ $TARGET == winarm64 ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    # Явно передаем инструменты, чтобы quirc не собрался под хост (Linux)
    make libquirc.a $MAKE_V -j$(nproc) CC="$CC" AR="$AR" CFLAGS="$CFLAGS" || return 1
    
    mkdir -p "$FFBUILD_DESTPREFIX/lib/" "$FFBUILD_DESTPREFIX/include/"
    cp libquirc.a "$FFBUILD_DESTPREFIX/lib/"
    cp lib/quirc.h "$FFBUILD_DESTPREFIX/include/"
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
