#!/bin/bash

SCRIPT_REPO="https://code.videolan.org/videolan/dav1d.git"
SCRIPT_COMMIT="62501cc7db378532d7e85ea434b70d57e1ba2cb0"

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
        --prefix="$FFBUILD_PREFIX"
        --libdir="$FFBUILD_PREFIX/lib"
        --cross-file="$FFBUILD_MESON_CROSS"
        --buildtype=release
        --default-library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false)
        -Dcpp_std=gnu++20
        -Dc_std=gnu17
        -Denable_asm=true
        -Denable_tools=false
        -Denable_tests=false
    )

    export NASM="/usr/bin/nasm"

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        -Dc_link_args="$LDFLAGS ${USELTO}" \
        -Dcpp_link_args="$LDFLAGS ${USELTO}" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    mkdir -p "$PC_DIR"
    if [ -d "$PC_DIR" ]; then
        find "$PC_DIR" -name "*.pc" | while read -r PC_FILE; do
            sed -i "s|^Cflags:.*|& -I\${includedir}/dav1d|" "$PC_FILE"
        done
        log_info "Cflags paths have been updated."
    fi
}

ffbuild_configure() {
    echo --enable-libdav1d
}

ffbuild_unconfigure() {
    echo --disable-libdav1d
}
