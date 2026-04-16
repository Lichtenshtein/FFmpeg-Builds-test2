#!/bin/bash

SCRIPT_REPO="https://code.videolan.org/videolan/libdvdread.git"
SCRIPT_COMMIT="e294cf7156ce8170ebb6786e21c4baf7aa5f48e4"

ffbuild_depends() {
    echo libudfread
    echo libdvdcss
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    # stop the static library from exporting symbols when linked into a shared lib
    sed -i 's/-DDVDREAD_API_EXPORT/-DDVDREAD_API_EXPORT_DISABLED/g' src/meson.build

    mkdir build && cd build

    local myconf=(
        --cross-file="$FFBUILD_MESON_CROSS"
        --buildtype=release
        --prefix="$FFBUILD_PREFIX"
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false )
        -Dc_std=c11
        -Dcpp_std=c++17
        -Ddefault_library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        -Denable_docs=false
        -Dlibdvdcss=enabled
        -Dwarning_level=1
        -Dwerror=false
    )

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS" \
        -Dc_link_args="$LDFLAGS" \
        -Dcpp_link_args="$LDFLAGS" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1
}

ffbuild_configure() {
    echo --enable-libdvdread
}

ffbuild_unconfigure() {
    echo --disable-libdvdread
}
