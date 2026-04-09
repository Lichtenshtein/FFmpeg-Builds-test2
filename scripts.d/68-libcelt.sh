#!/bin/bash

SCRIPT_REPO="https://github.com/MartinEesmaa/celt.git"
SCRIPT_COMMIT="3671477887c2ca8414f2aa1cabbca4beeb0f7812"

ffbuild_depends() {
    echo libogg
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    ./autogen.sh

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --enable-custom-modes # enable non-Opus modes, like 44.1 kHz and powers of two
        --enable-float-approx # fast approximations for floating point
        --disable-oggtest
        --with-ogg=no
        #--enable-fixed-point # compile as fixed-point insted of floating-point
        #--enable-experimental-postfilter
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
        )
    fi

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
    echo --enable-libcelt
}

ffbuild_unconfigure() {
    echo --disable-libcelt
}
