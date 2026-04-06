#!/bin/bash

SCRIPT_REPO="https://code.videolan.org/videolan/dav1d.git"
SCRIPT_COMMIT="60507bffc0b13e7a81753a51005dbbeba4b23018"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    mkdir build && cd build

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --libdir="$FFBUILD_PREFIX/lib"
        --cross-file=/cross.meson
        --buildtype=release
        --default-library=static
        -Dcpp_std=c++17
        -Dc_std=c11
        -Denable_asm=true
        -Denable_tools=false
        -Denable_tests=false
    )

    # Обработка LTO (Meson использует b_lto)
    if [[ "$USE_LTO" == "1" ]]; then
        myconf+=( -Db_lto=true )
    fi

    # Принудительно указываем путь к nasm, если Meson его "теряет"
    export NASM="/usr/bin/nasm"

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS" \
        -Dc_link_args="$LDFLAGS" \
        -Dcpp_link_args="$LDFLAGS" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

}

ffbuild_configure() {
    echo --enable-libdav1d
}

ffbuild_unconfigure() {
    echo --disable-libdav1d
}
