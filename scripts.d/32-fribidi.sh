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
        --buildtype=release
        --cross-file=/cross.meson
        --default-library=$([ "${PREFER_SHARED}" == "1" ] && echo static || echo shared)
        --prefix="$FFBUILD_PREFIX"
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false )
        -Dbin=false
        -Dc_std=c11
        -Dcpp_std=c++17
        -Ddocs=false
        -Dtests=false
    )

    local static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DFRIBIDI_LIB_STATIC"

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS $static_flags" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS $static_flags" \
        -Dc_link_args="$LDFLAGS" \
        -Dcpp_link_args="$LDFLAGS" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local PC_FILE="$PC_DIR/fribidi.pc"
    if [[ -f "$PC_FILE" ]]; then
        if ! grep -q "\$static_flags" "$PC_FILE"; then
            sed -i 's/Cflags:/& $static_flags/' "$PC_FILE"
        fi
    fi
}

ffbuild_cppflags() {
    echo "$static_flags"
}

ffbuild_configure() {
    echo --enable-libfribidi
}

ffbuild_unconfigure() {
    echo --disable-libfribidi
}
