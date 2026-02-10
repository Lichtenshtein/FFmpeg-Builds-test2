#!/bin/bash

SCRIPT_REPO="https://github.com/GNOME/libxml2.git"
SCRIPT_COMMIT="9827e6e44652555992e168609abf94e4237ca944"

ffbuild_depends() {
    echo base
    echo libiconv
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
}

ffbuild_dockerbuild() {
    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --without-python
        --disable-maintainer-mode
        --without-modules
        --disable-shared
        --enable-static
        --with-pic
        --with-icu=no
        --with-zlib=yes
        --with-lzma=yes
        --with-iconv="$FFBUILD_PREFIX" # Указываем наш префикс явно
    )

    ./autogen.sh "${myconf[@]}"

    # Исправляем Makefile, если он решит, что iconv — это часть libc (в Windows это не так)
    sed -i 's/-liconv//g' Makefile
    sed -i 's/LIBS = /LIBS = -liconv /' Makefile

    make -j$(nproc)
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-libxml2
}

ffbuild_unconfigure() {
    echo --disable-libxml2
}
