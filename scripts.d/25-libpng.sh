#!/bin/bash

SCRIPT_REPO="https://github.com/glennrp/libpng.git"
SCRIPT_COMMIT="c3e304954a9cfd154bc0dfbfea2b01cd61d6546d"

ffbuild_depends() {
    echo base
    echo zlib
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
        --enable-hardware-optimizations
        --enable-intel-sse
        --disable-tests
        --disable-tools
        --with-pic
        --with-zlib-prefix="$FFBUILD_PREFIX"
    )

    CFLAGS="$CFLAGS" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS" \
    LDFLAGS="$LDFLAGS" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    # Создаем стандартные симлинки для совместимости
    # Многие старые пакеты ищут libpng16.pc или libpng.pc
    local PC_LINK="$PC_DIR/libpng.pc"
    ln -sf libpng16.pc "$PC_LINK"

}
