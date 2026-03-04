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
    set -e

    local ICU_LIBS=$(pkg-config --libs --static icu-uc icu-i18n)
    local DEP_LIBS="$ICU_LIBS $(pkg-config --libs --static zlib liblzma) $LIBS"

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

    ./autogen.sh "${myconf[@]}" \
        CFLAGS="$CFLAGS -DLIBXML_STATIC -DXML_STATIC" \
        CPPFLAGS="$CPPFLAGS -DLIBXML_STATIC -DXML_STATIC" \
        LIBS="$DEP_LIBS"

    # Исправляем Makefile, если он решит, что iconv — это часть libc (в Windows это не так)
    # sed -i 's/-liconv//g' Makefile
    # sed -i 's/LIBS = /LIBS = -liconv /' Makefile

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/libxml-2.0.pc"
    if [[ -f "$PC_FILE" ]]; then
        # Добавляем ICU в секцию Requires.private, чтобы pkg-config сам разматывал дерево либ
        if grep -q "Requires.private:" "$PC_FILE"; then
            sed -i '/^Requires.private:/ s/$/ icu-uc icu-i18n/' "$PC_FILE"
        else
            echo "Requires.private: icu-uc icu-i18n zlib liblzma" >> "$PC_FILE"
        fi
        # Добавляем системные либы и рантайм C++ в Libs.private (порядок важен)
        # Системные либы из $LIBS (ws2_32, bcrypt и т.д.) должны быть в конце
        sed -i "/^Libs.private:/ s/$/ -lstdc++ -liconv -lintl -lws2_32 -lbcrypt/" "$PC_FILE"
        # Гарантируем наличие флагов статики в Cflags pc-файла
        sed -i "/^Cflags:/ s/$/ -DLIBXML_STATIC -DXML_STATIC/" "$PC_FILE"
    fi

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
