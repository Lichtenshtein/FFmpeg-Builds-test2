#!/bin/bash

SCRIPT_REPO="https://github.com/zapping-vbi/zvbi.git"
SCRIPT_COMMIT="41477c97c8edf7a01f1594b2a95b94f0117eed21"

ffbuild_depends() {
    echo base
    echo libiconv
    echo libicu
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
        --with-pic
        --without-doxygen
        --without-x
        --disable-dvb
        --disable-bktr
        --enable-nls # libicu
        --disable-proxy
        --disable-examples
        --disable-tests
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
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -C src -j$(nproc) $MAKE_V || return 1
    make -C src install DESTDIR="$FFBUILD_DESTDIR" || return 1
    make SUBDIRS=. install DESTDIR="$FFBUILD_DESTDIR" || return 1

    mkdir -p "$PC_DIR"
    ln -sf zvbi-0.2.pc "$PC_DIR/zvbi.pc"
    ln -sf zvbi-0.2.pc "$PC_DIR/libzvbi.pc"
}

ffbuild_configure() {
    echo --enable-libzvbi
}

ffbuild_unconfigure() {
    echo --disable-libzvbi
}
