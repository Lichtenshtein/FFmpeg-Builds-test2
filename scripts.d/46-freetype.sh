#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/freetype/freetype.git"
SCRIPT_COMMIT="28407bc8cd1a3da43df7b11c40bc5c24b9883ac6"

ffbuild_depends() {
    echo brotli
    echo bzlib
    echo harfbuzz
    echo libpng
    echo librsvg
    echo zlib
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

    # Собираем либы для линковки (важно для тестов в configure)
    local FT_LIBS=$(pkg-config --libs --static harfbuzz librsvg-2.0 libpng zlib libbrotlidec bzip2)

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
    
    # Важно для статической линковки FFmpeg: прописываем все зависимости в Libs.private
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/freetype2.pc"
    if [[ -f "$PC_FILE" ]]; then
        # Используем рекурсивный вывод pkg-config для финального патча
        local ALL_PRIVATE=$(pkg-config --libs --static harfbuzz librsvg-2.0 libpng zlib libbrotlidec bzip2)
        sed -i "s|^Libs.private:.*|Libs.private: $ALL_PRIVATE $LIBS|" "$PC_FILE"
    fi
    
    get_deps_list
}

ffbuild_configure() {
    echo --enable-libfreetype
}

ffbuild_unconfigure() {
    echo --disable-libfreetype
}
