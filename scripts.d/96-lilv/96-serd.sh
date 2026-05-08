#!/bin/bash

SCRIPT_REPO="https://github.com/drobilla/serd.git"
SCRIPT_COMMIT="1fd12ee91b4dfc124ce4435b1fe52b3a69c75255"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build && cd build

    local myconf=(
        --buildtype=release
        --default-library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        --prefix="$FFBUILD_PREFIX"
        --cross-file="$FFBUILD_MESON_CROSS"
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false)
        -Dc_std=gnu17
        -Dcpp_std=gnu++20
        -Ddocs=disabled
        -Dhtml=disabled
        -Dman=disabled
        -Dman_html=disabled
        -Dsinglehtml=disabled
        -Dstatic=$([ "${PREFER_SHARED}" == "1" ] && echo false || echo true)
        -Dtests=disabled
        -Dtools=disabled
    )

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        -Dc_link_args="$LDFLAGS ${USELTO}" \
        -Dcpp_link_args="$LDFLAGS ${USELTO}" || return 1

    ninja -j"$(nproc)" $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1
}
