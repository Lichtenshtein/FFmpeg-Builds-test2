#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/pixman/pixman.git"
SCRIPT_COMMIT="f824cac6478971c0f71e4dfe8a60ebf70224076a"

ffbuild_depends() {
    echo libpng
    echo glib2
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir build && cd build

    local DEP_LIBS="-lpng16 -lgio-2.0 -lgthread-2.0 -lglib-2.0 -lz -lintl -liconv -lcharset"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --cross-file=/cross.meson
        --buildtype=release
        --default-library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false)
        -Dcpp_std=c++17
        -Dc_std=c11
        -Dtests=disabled
        -Ddemos=disabled
        -Dgtk=disabled
        -Dopenmp=disabled
    )

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-Dpixman_static"

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS $static_flags" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS $static_flags" \
        -Dc_link_args="$LDFLAGS $DEP_LIBS" \
        -Dcpp_link_args="$LDFLAGS $DEP_LIBS" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local PC_FILE="$PC_DIR/pixman-1.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i "/^Cflags:/ s/[[:space:]]*-pthread//g" "$PC_FILE"
        if ! grep -q "$static_flags" "$PC_FILE"; then
            sed -i "/^Cflags:/ s/$/ $static_flags/" "$PC_FILE"
        fi
    fi
}
