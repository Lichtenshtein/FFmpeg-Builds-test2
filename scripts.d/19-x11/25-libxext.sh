#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/xorg/lib/libxext.git"
SCRIPT_COMMIT="2a694ba264ccdb205909909abfe8b136f9156ebe"

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
        --without-xmlto
        --without-fop
        --without-xsltproc
        --without-lint
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
    CPPFLAGS="$CPPFLAGS -D_GNU_SOURCE" \
    CXXFLAGS="$CXXFLAGS ${USELTO}" \
    LDFLAGS="$RAW_LDFLAGS ${USELTO}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    gen-implib "$FFBUILD_DESTPREFIX"/lib/{libXext.so.6,libXext.a}
    rm "$FFBUILD_DESTPREFIX"/lib/libXext{.so*,.la}
}
