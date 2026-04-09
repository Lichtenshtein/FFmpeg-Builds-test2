#!/bin/bash

SCRIPT_REPO="https://github.com/BtbN/gmplib.git"
SCRIPT_COMMIT="9994908f090c694f8a152d660dc6852e0c48557a"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    # autoupdate
    # autoreconf -i
    ./.bootstrap

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --enable-maintainer-mode
        --enable-fat
        --with-pic
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    CFLAGS="$CFLAGS ${USELTO}" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS ${USELTO}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1
}

ffbuild_configure() {
    echo --enable-gmp
}

ffbuild_unconfigure() {
    echo --disable-gmp
}
