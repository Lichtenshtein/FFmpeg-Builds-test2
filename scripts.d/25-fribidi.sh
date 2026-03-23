#!/bin/bash

SCRIPT_REPO="https://github.com/fribidi/fribidi.git"
SCRIPT_COMMIT="b28f43bd3e8e31a5967830f721bab218c1aa114c"
# SCRIPT_REPO="https://github.com/Treata11/fribidi.git"
# SCRIPT_COMMIT="1a1ac31d25eeee9efd3d496b04b3b29ae81b8809"

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
        --cross-file=/cross.meson
        --buildtype=release
        --default-library=static
        -Dcpp_std=c++17
        -Dc_std=c11
        -Dbin=false
        -Ddocs=false
        -Dtests=false
    )

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS -DFRIBIDI_LIB_STATIC" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS -DFRIBIDI_LIB_STATIC" \
        -Dc_link_args="$LDFLAGS" \
        -Dcpp_link_args="$LDFLAGS" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local PC_FILE="$PC_DIR/fribidi.pc"
    if [[ -f "$PC_FILE" ]]; then
        if ! grep -q "\-DFRIBIDI_LIB_STATIC" "$PC_FILE"; then
            sed -i 's/Cflags:/& -DFRIBIDI_LIB_STATIC/' "$PC_FILE"
        fi
    fi

}

ffbuild_cppflags() {
    echo "-DFRIBIDI_LIB_STATIC"
}

ffbuild_configure() {
    echo --enable-libfribidi
}

ffbuild_unconfigure() {
    echo --disable-libfribidi
}
