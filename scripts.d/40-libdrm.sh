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
    mkdir build && cd build

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        -Dcpp_std=c++17
        -Dc_std=c11
        -Ddefault_library=shared
        -Dudev=false
        -Dcairo-tests=disabled
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
            --cross-file=/cross.meson
        )
    else
        echo "Unknown target"
        return 1
    fi

    meson setup "${myconf[@]}" .. \
        -Dc_args="$RAW_CFLAGS $CPPFLAGS" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS" \
        -Dc_link_args="$RAW_LDFLAGS" \
        -Dcpp_link_args="$RAW_LDFLAGS" || return 1

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
