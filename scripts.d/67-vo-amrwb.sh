#!/bin/bash

SCRIPT_REPO="https://github.com/mstorsjo/vo-amrwbenc.git"
SCRIPT_COMMIT="884dd247dbeb6b2bd2cd3291c4872de95700291f"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    autoreconf -i

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --with-pic
        --disable-example
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
    echo --enable-libvo-amrwbenc
}

ffbuild_unconfigure() {
    echo --disable-libvo-amrwbenc
}
