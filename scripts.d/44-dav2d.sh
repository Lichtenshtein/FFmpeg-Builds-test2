#!/bin/bash

SCRIPT_REPO="https://code.videolan.org/videolan/dav2d.git"
SCRIPT_COMMIT="67ec0a68f6245cebd407eacdf6c7dd1ac8a58165"

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
        --cross-file="$FFBUILD_MESON_CROSS"
        --prefix="$FFBUILD_PREFIX"
        --libdir="lib"
        --buildtype=release
        --default-library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        -Dc_std=gnu17
        -Denable_asm=true
        -Denable_tools=false
        -Denable_examples=false
        -Denable_tests=false
        -Denable_seek_stress=false
        -Denable_docs=false
        -Dlogging=true
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( -Db_lto=true )

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        -Dc_link_args="$LDFLAGS ${USELTO}${USELTO_L}" \
        -Dcpp_link_args="$LDFLAGS ${USELTO}${USELTO_L}" || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # if ls "$PC_DIR"/*dav2d*.pc >/dev/null 2>&1; then
        # for PC_FILE in "$PC_DIR"/*dav2d*.pc; do
            # [[ -e "$PC_FILE" ]] || continue
            # if ! grep -qF "Libs.private" "$PC_FILE"; then
                # echo "Libs.private: $WIN_LIBS" >> "$PC_FILE"
            # fi
        # done
    # fi
}

ffbuild_configure() {
    echo --enable-libdav2d
}

ffbuild_unconfigure() {
    echo --disable-libdav2d
}
