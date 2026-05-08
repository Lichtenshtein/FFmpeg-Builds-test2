#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/mesa/drm.git"
SCRIPT_COMMIT="369990d9660a387f618d0eedc341eb285016243b"

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
        -Dcpp_std=gnu++20
        -Dc_std=gnu17
        -Ddefault_library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        -Dudev=false
        -Dcairo-tests=disabled
        -Dtests=false
        -Dvalgrind=disabled
        -Dexynos=disabled
        -Dfreedreno=disabled
        -Domap=disabled
        -Detnaviv=disabled
        -Dintel=enabled
        -Dnouveau=enabled
        -Dradeon=enabled
        -Damdgpu=enabled
    )

    if [[ $TARGET == linux* ]]; then
        myconf+=(
            --cross-file="$FFBUILD_MESON_CROSS"
        )
    fi

    meson setup "${myconf[@]}" .. \
        -Dc_args="$RAW_CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        -Dc_link_args="$RAW_LDFLAGS ${USELTO}" \
        -Dcpp_link_args="$RAW_LDFLAGS ${USELTO}" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    gen-implib "$FFBUILD_DESTPREFIX"/lib/{libdrm.so.2,libdrm.a}
    rm "$FFBUILD_DESTPREFIX"/lib/libdrm*.so*

    echo "Libs: -ldl" >> "$PC_DIR/libdrm.pc"
}

ffbuild_configure() {
    echo --enable-libdrm
}

ffbuild_unconfigure() {
    echo --disable-libdrm
}
