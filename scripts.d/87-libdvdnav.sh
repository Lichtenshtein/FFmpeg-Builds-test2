#!/bin/bash

SCRIPT_REPO="https://code.videolan.org/videolan/libdvdnav.git"
SCRIPT_COMMIT="cf112772bf626f76a913efca5b883a381e4c123a"

ffbuild_depends() {
    echo libudfread
    echo libdvdcss
    echo libdvdread
}

ffbuild_enabled() {
    [[ $VARIANT == lgpl* ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    # stop the static library from exporting symbols when linked into a shared lib
    sed -i 's/SUPPORT_ATTRIBUTE_VISIBILITY_DEFAULT/SUPPORT_ATTRIBUTE_VISIBILITY_DEFAULT_DISABLED/g' meson.build
    sed -i 's/-DLIBDVDCSS_EXPORTS/-DLIBDVDCSS_EXPORTS_DISABLED/g' src/meson.build

    mkdir -p build && cd build

    local myconf=(
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false )
        --prefix="$FFBUILD_PREFIX"
        -Ddefault_library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        -Dcpp_std=c++17
        -Dc_std=c11
        -Denable_docs=false
        -Denable_examples=false
    )

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --cross-file="$FFBUILD_MESON_CROSS"
        )
    fi

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS" \
        -Dc_link_args="$LDFLAGS" \
        -Dcpp_link_args="$LDFLAGS" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1
}

ffbuild_configure() {
    echo --enable-libdvdnav
}

ffbuild_unconfigure() {
    echo --disable-libdvdnav
}
