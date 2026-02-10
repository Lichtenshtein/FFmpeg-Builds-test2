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
    export PKG_CONFIG_PATH="$FFBUILD_PREFIX/lib/pkgconfig"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --without-python
        --without-icu
        --without-modules
        --disable-maintainer-mode
        --disable-shared
        --enable-static
        --with-pic
        --with-icu=no
        --with-zlib=yes
        --with-lzma=yes
        --with-iconv=yes
    )

    # Принудительно подтягиваем флаги из pkg-config, чтобы застраховаться
    export CFLAGS="$CFLAGS $(pkg-config --cflags zlib liblzma)"
    # export LDFLAGS="$LDFLAGS $(pkg-config --libs zlib liblzma)"
    export CPPFLAGS="-I$FFBUILD_PREFIX/include"
    export LDFLAGS="$LDFLAGS -L$FFBUILD_PREFIX/lib"

    ./autogen.sh "${myconf[@]}"

    # Исправляем Makefile, если он решит, что iconv — это часть libc (в Windows это не так)
    sed -i 's/-liconv//g' Makefile
    sed -i 's/LIBS = /LIBS = -liconv /' Makefile

    make -j$(nproc)
    make install DESTDIR="$FFBUILD_DESTDIR"

    # копируем результат в префикс для следующих скриптов
    cp -r "$FFBUILD_DESTDIR$FFBUILD_PREFIX"/. "$FFBUILD_PREFIX"/
}

ffbuild_configure() {
    echo --enable-libxml2
}

ffbuild_unconfigure() {
    echo --disable-libxml2
}
