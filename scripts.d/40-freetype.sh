#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/freetype/freetype.git"
SCRIPT_COMMIT="28407bc8cd1a3da43df7b11c40bc5c24b9883ac6"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" . "
    echo "git-mini-clone \"https://github.com/nyorain/dlg.git\" \"master\" subprojects/dlg"
}

ffbuild_dockerbuild() {
    ./autogen.sh

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
        CPPFLAGS="-I$FFBUILD_PREFIX/include"

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"
    
    # Важно для статической линковки FFmpeg
    sed -i 's/-lfreetype/-lfreetype -lharfbuzz -lpng -lz -lbz2 -lbrotlidec -lbrotlicommon/' "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/freetype2.pc"
}

ffbuild_configure() {
    echo --enable-libfreetype
}

ffbuild_unconfigure() {
    echo --disable-libfreetype
}
