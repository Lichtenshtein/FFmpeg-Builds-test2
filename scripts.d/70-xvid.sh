#!/bin/bash

# SCRIPT_REPO="https://svn.xvid.org/trunk/xvidcore"
# SCRIPT_REV="2202"

SCRIPT_REPO="https://github.com/m-ab-s/xvid.git"
SCRIPT_COMMIT="04bccf378d628d78efe28e39b0a94f0c206664a9"
SCRIPT_BRANCH="mabs"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    cd build/${STAGENAME}/xvidcore/build/generic

    # The original code fails on a two-digit major...
    sed -i 's/GCC_MAJOR=.*/GCC_MAJOR=14/' configure.in
    sed -i 's/GCC_MINOR=.*/GCC_MINOR=0/' configure.in

    ./bootstrap.sh

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        # other existing options
        #--enable-idebug
        #--enable-iprofile
        #--enable-gnuprofile
        #--disable-assembly
        #--disable-pthread
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    # Xvid падает с LTO
    CFLAGS="$CFLAGS ${NOLTO} -std=gnu99 -fcommon" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS ${NOLTO}" \
    LDFLAGS="$LDFLAGS ${NOLTO}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1
}

ffbuild_configure() {
    echo --enable-libxvid
}

ffbuild_unconfigure() {
    echo --disable-libxvid
}
