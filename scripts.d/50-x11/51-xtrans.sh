#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/xorg/lib/libxtrans.git"
SCRIPT_COMMIT="693d28a76024a2a0a28eef25037bcb7558b8bbfa"

ffbuild_enabled() {
    [[ $TARGET != linux* ]] && return 1
    return 0
}

ffbuild_dockerbuild() {
    autoreconf -i

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --without-xmlto
        --without-fop
        --without-xsltproc
    )

    if [[ $TARGET == linux* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
        )
    fi

    CFLAGS="$RAW_CFLAGS" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS" \
    LDFLAGS="$RAW_LDFLAGS" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    cp -r "$FFBUILD_DESTPREFIX"/share/aclocal/. /usr/share/aclocal
}
