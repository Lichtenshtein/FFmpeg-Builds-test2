#!/bin/bash

SCRIPT_REPO="https://github.com/GNOME/libxml2.git"
SCRIPT_COMMIT="2cc5834033db61fb7adc242fb15f7d1e13f66c14"

ffbuild_depends() {
    echo base
    echo libiconv
    echo zlib
    echo libicu
    echo xz
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    export PKG_CONFIG_PATH="$FFBUILD_PREFIX/lib/pkgconfig"

    # для libxml2 статик-флаг часто требует и XML_STATIC, и LIBXML_STATIC
    export CFLAGS="$CFLAGS -DXML_STATIC -DLIBXML_STATIC"
    export CPPFLAGS="$CPPFLAGS -DXML_STATIC -DLIBXML_STATIC"

    # -lstdc++ подхватит зависимости ICU (libsicuuc) при сборке xmllint
    export LIBS="-lstdc++"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --without-python
        --without-debug
        --without-docs
        --without-modules
        --disable-maintainer-mode
        --disable-shared
        --enable-static
        --with-pic
        --with-icu
        --with-thread-alloc
        --with-winpath
        --with-zlib
        --with-iconv
        --with-tls
    )

    ./autogen.sh "${myconf[@]}"

    # Исправляем Makefile, если он решит, что iconv — это часть libc (в Windows это не так)
    # sed -i 's/-liconv//g' Makefile
    # sed -i 's/LIBS = /LIBS = -liconv /' Makefile

    make -j$(nproc) $MAKE_V LIBS="-lstdc++ $(pkg-config --libs --static icu-uc zlib liblzma)"
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Libxml2 часто забывает добавить -liconv и -lws2_32 в Libs.private для Windows
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/libxml-2.0.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i '/^Libs.private:/ s/$/ -lstdc++ -liconv -lws2_32 -lbcrypt/' "$PC_FILE"
    fi

    # Вызываем отладку зависимостей
    get_deps_list
}

ffbuild_cppflags() {
    echo "-DLIBXML_STATIC -DXML_STATIC"
}

ffbuild_configure() {
    echo --enable-libxml2
}

ffbuild_unconfigure() {
    echo --disable-libxml2
}
