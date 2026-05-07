#!/bin/bash

SCRIPT_REPO="https://github.com/rocky/libcdio-paranoia.git"
SCRIPT_COMMIT="307fa2e43dad116b5a9ffe36424fbfd08da30a8f"

ffbuild_depends() {
    echo libiconv
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    local DEP_LIBS="-liconv -lcharset"

    autoreconf -if

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-example-progs
        --disable-maintainer-mode
        --enable-cpp-progs=no
        --with-pic
        ac_cv_func_clock_gettime=no
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    CFLAGS="$CFLAGS ${USELTO}${USELTO_C}" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS $DEP_LIBS ${USELTO}" \
    LIBS="$LIBS $DEP_LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1
}

ffbuild_configure() {
    echo --enable-libcdio
}

ffbuild_unconfigure() {
    echo --disable-libcdio
}
