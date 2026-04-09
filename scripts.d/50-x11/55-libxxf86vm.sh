#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/xorg/lib/libxxf86vm.git"
SCRIPT_COMMIT="7f200bf00e3e288e47265c01decc401616c57f10"

ffbuild_enabled() {
    [[ $TARGET != linux* ]] && return 1
    return 0
}

ffbuild_dockerbuild() {
    set -e

    autoreconf -i

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --with-pic
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    if [[ $TARGET == linuxarm64 ]]; then
        myconf+=(
            --disable-malloc0returnsnull
        )
    fi

    if [[ $TARGET == linux* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
        )
    fi

    CFLAGS="$RAW_CFLAGS ${USELTO}" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS ${USELTO}" \
    LDFLAGS="$RAW_LDFLAGS ${USELTO}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    gen-implib "$FFBUILD_DESTPREFIX"/lib/{libXxf86vm.so.1,libXxf86vm.a}
    rm "$FFBUILD_DESTPREFIX"/lib/libXxf86vm{.so*,.la}
}
