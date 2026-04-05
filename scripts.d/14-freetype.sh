#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/freetype/freetype.git"
SCRIPT_COMMIT="67c52a0b68eaeb7ae1f2248202924883c4a232d0"

ffbuild_depends() {
    echo zlib
    echo bzlib
    echo brotli
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-submodule-clone"
}

ffbuild_dockerbuild() {
    set -e

    ./autogen.sh

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-shared
        --enable-static
        --with-pic
        --without-harfbuzz
        --without-png
        --with-zlib
        --with-bzip2
        --with-brotli
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( --enable-lto )

    CFLAGS="$CFLAGS" \
    LDFLAGS="$LDFLAGS" \
    CPPFLAGS="$CPPFLAGS -DFT2_BUILD_LIBRARY" \
    CXXFLAGS="$CXXFLAGS -DFT2_BUILD_LIBRARY" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    # Создаем симлинк
    local PC_LINK="$PC_DIR/freetype.pc"
    ln -sf freetype2.pc "$PC_LINK"

}
