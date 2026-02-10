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
        --with-zlib="$FFBUILD_PREFIX"   # Явно указываем путь к zlib
        --with-lzma="$FFBUILD_PREFIX"   # Явно указываем путь к xz/lzma
        --with-iconv="$FFBUILD_PREFIX"  # Явно указываем путь к iconv
    )

    # Принудительно подтягиваем флаги из pkg-config, чтобы застраховаться
    export CFLAGS="$CFLAGS $(pkg-config --cflags zlib liblzma)"
    export LDFLAGS="$LDFLAGS $(pkg-config --libs zlib liblzma)"

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
