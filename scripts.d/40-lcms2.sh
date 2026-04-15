#!/bin/bash

SCRIPT_REPO="https://github.com/mm2/Little-CMS.git"
SCRIPT_COMMIT="a4c87ebbfdd3b1c493e5ecca5f36d991b137fc95"

ffbuild_depends() {
    echo libjpeg-turbo
    echo libtiff
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    mkdir build && cd build

    local DEP_LIBS="-ltiffxx -ltiff -lturbojpeg -ljpeg -ljbig -lzstd -llzma -lz"
    local WIN_LIBS="$LIBS"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --pkg-config-path="$PKG_CONFIG_PATH"
        --cross-file=/cross.meson
        -Ddefault_library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false)
        -Dcpp_std=c++17
        -Dc_std=c11
        -Dutils=false
        -Dfastfloat=true
        -Dthreaded=true
        -Dtests=disabled
    )

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS" \
        -Dc_link_args="$LDFLAGS $WIN_LIBS" \
        -Dcpp_link_args="$LDFLAGS $WIN_LIBS" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local PC_FILE="$PC_DIR/lcms2.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i '/^Cflags:/ s/[[:space:]]*-pthread//g' "$PC_FILE"
    fi
}

ffbuild_configure() {
    echo --enable-lcms2
}

ffbuild_unconfigure() {
    echo --disable-lcms2
}
