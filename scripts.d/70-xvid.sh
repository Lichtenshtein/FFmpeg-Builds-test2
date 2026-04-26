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

    cd xvidcore/build/generic

    # The original code fails on a two-digit major...
    sed -i 's/GCC_MAJOR=.*/GCC_MAJOR=4/' configure.in
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
        myconf+=( --enable-shared ) || \
        myconf+=( --enable-static )

    # Xvid падает с LTO
    CFLAGS="$CFLAGS ${NOLTO} -fcommon" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS ${NOLTO}" \
    LDFLAGS="$LDFLAGS ${NOLTO}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    # У Xvid есть баг: он может пытаться собрать .so даже для Windows
    # Исправим Makefile, если он решит собирать разделяемую библиотеку при статике
    [[ "${PREFER_SHARED}" != "1" ]] && sed -i 's/SHARED_LIB =.*/SHARED_LIB =/' Makefile

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    if [[ -d "$FFBUILD_DESTPREFIX/lib64" ]]; then
        mv "$FFBUILD_DESTPREFIX/lib64"/* "$FFBUILD_DESTPREFIX/lib/"
        rmdir "$FFBUILD_DESTPREFIX/lib64"
    fi
}

ffbuild_configure() {
    echo --enable-libxvid
}

ffbuild_unconfigure() {
    echo --disable-libxvid
}
