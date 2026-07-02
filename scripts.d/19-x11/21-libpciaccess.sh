#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/xorg/lib/libpciaccess.git"
SCRIPT_COMMIT="38e6f15f839fba2c49982e7ad61cde681fd5d4d6"

ffbuild_depends() {
    echo base
    echo zlib
}

ffbuild_enabled() {
    [[ $TARGET != linux* ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build && cd build

    local myconf=(
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false)
        --prefix="$FFBUILD_PREFIX"
        --buildtype=release
        --default-library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        -Dcpp_std=gnu++20
        -Dc_std=gnu17
        -Dzlib=enabled
    )

    if [[ $TARGET == linux* ]]; then
        myconf+=(
            --cross-file="$FFBUILD_MESON_CROSS"
        )
    fi

    meson setup "${myconf[@]}" .. \
        -Dc_args="$RAW_CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        -Dc_link_args="$RAW_LDFLAGS ${USELTO}${USELTO_L}" \
        -Dcpp_link_args="$RAW_LDFLAGS ${USELTO}${USELTO_L}" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    gen-implib "$INSTALL_ROOT"/lib/{libpciaccess.so.0,libpciaccess.a}
    rm "$INSTALL_ROOT"/lib/libpciaccess.so*

    echo "Libs: -ldl" >> "$PC_DIR/pciaccess.pc"
}
