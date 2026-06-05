#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/xorg/proto/xorgproto.git"
SCRIPT_COMMIT="fcb7e9a1a0b593a44740d83b0babddd331fea830"

ffbuild_enabled() {
    [[ $TARGET != linux* ]] && return 1
    return 0
}

ffbuild_dockerbuild() {
    set -e

    autoreconf -i

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    if [[ $TARGET == linux* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
        )
    fi

    CFLAGS="$RAW_CFLAGS ${USELTO}${USELTO_C}" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$RAW_LDFLAGS ${USELTO}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1
}
