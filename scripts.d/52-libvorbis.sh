#!/bin/bash

SCRIPT_REPO="https://github.com/xiph/vorbis.git"
SCRIPT_COMMIT="2d79800b6751dddd4b8b4ad50832faa5ae2a00d9"

ffbuild_depends() {
    echo base
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
        --host="$FFBUILD_TOOLCHAIN"
        --disable-shared
        --enable-static
        --disable-oggtest
        --disable-docs
        --disable-examples
    )

    CFLAGS="$CFLAGS" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS" \
    LDFLAGS="$LDFLAGS" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

}

ffbuild_configure() {
    echo --enable-libvorbis
}

ffbuild_unconfigure() {
    echo --disable-libvorbis
}
