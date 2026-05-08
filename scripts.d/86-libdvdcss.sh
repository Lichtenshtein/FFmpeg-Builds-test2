#!/bin/bash

SCRIPT_REPO="https://code.videolan.org/videolan/libdvdcss.git"
SCRIPT_COMMIT="2682a4a7ed782e700a5b920f6f85c4f9736921c3"

ffbuild_depends() {
    echo libudfread
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

    mkdir build && cd build

    local myconf=(
        --cross-file="$FFBUILD_MESON_CROSS"
        --prefix="$FFBUILD_PREFIX"
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false)
        -Dcpp_std=gnu++20
        -Dc_std=gnu17
        -Ddefault_library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        -Denable_docs=false
        -Denable_examples=false
        )

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -Dprint_error=dvdcss_print_error -Dprint_debug=dvdcss_print_debug" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -Dprint_error=dvdcss_print_error -Dprint_debug=dvdcss_print_debug" \
        -Dc_link_args="$LDFLAGS ${USELTO}" \
        -Dcpp_link_args="$LDFLAGS ${USELTO}" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1
}
