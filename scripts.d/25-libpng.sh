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
        --disable-tests
        --disable-tools
        --with-pic
    )

    export CPPFLAGS="$CPPFLAGS -I$FFBUILD_PREFIX/include"

    ./configure "${myconf[@]}"
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Создаем стандартные симлинки для совместимости
    # Многие старые пакеты ищут libpng16.pc или libpng.pc
    cd "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig"
    ln -sf libpng16.pc libpng.pc

    get_deps_list
}
