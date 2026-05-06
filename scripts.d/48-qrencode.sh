#!/bin/bash

SCRIPT_REPO="https://github.com/GerHobbelt/libqrencode.git"
SCRIPT_COMMIT="21c31742474699306cafb64ca2e7b293cd96c57d"

ffbuild_depends() {
    echo libpng
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    autoreconf -if

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --without-tools # build utility tools
        --without-tests
        --enable-thread-safety # make the library thread-safe
        --with-pic
        #--without-png # disable PNG support
        #--enable-gcov # write coverage information suitable for gcov
        #--enable-gprof # write coverage information suitable for gprof
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
        )
    fi

    CFLAGS="$CFLAGS ${USELTO}${USELTO_C}" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1
}

ffbuild_configure() {
    echo --enable-libqrencode
}

ffbuild_unconfigure() {
    echo --disable-libqrencode
}
