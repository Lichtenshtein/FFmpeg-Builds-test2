#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/freetype/freetype.git"
SCRIPT_COMMIT="28407bc8cd1a3da43df7b11c40bc5c24b9883ac6"

ffbuild_depends() {
    echo fontconfig
    echo freetype
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-mini-clone \"https://github.com/nyorain/dlg.git\" \"master\" subprojects/dlg"
}

ffbuild_dockerbuild() {
    set -e
    ./autogen.sh

    # Получаем флаги зависимостей, чтобы configure их увидел в статике
    local FT_LIBS=$(pkg-config --libs --static harfbuzz libpng zlib libbrotlidec bzip2)


    ./configure \
        --prefix="$FFBUILD_PREFIX" \
        --host="$FFBUILD_TOOLCHAIN" \
        --disable-shared \
        --enable-static \
        --with-harfbuzz \
        --with-pic \
        --with-png \
        --with-zlib \
        --with-bzip2 \
        --with-brotli \
        LDFLAGS="-L$FFBUILD_PREFIX/lib" \
        CPPFLAGS="$CPPFLAGS -I$FFBUILD_PREFIX/include" \
        LIBS="$FT_LIBS $LIBS"

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/freetype2.pc"
    if [[ -f "$PC_FILE" ]]; then

        sed -i "/^Libs.private:/ s/$/ -lbrotlidec -lbrotlicommon -lharfbuzz -lpng16 -lz -lbz2/" "$PC_FILE"
    fi

    get_deps_list
}