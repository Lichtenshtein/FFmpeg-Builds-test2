#!/bin/bash

SCRIPT_REPO="https://github.com/xiph/speex.git"
SCRIPT_COMMIT="05895229896dc942d453446eba6f9f5ddcf95422"

ffbuild_depends() {
    echo base
    echo fftw3
}

ffbuild_enabled() {
    [[ $TARGET == *arm64 ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir build && cd build

    local myconf=(
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false )
        --prefix="$FFBUILD_PREFIX"
        --cross-file=/cross.meson
        --buildtype=release
        -Dcpp_std=c++17
        -Dc_std=c11
        -Ddefault_library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        -Dtools=disabled
        -Dtest-binaries=disabled
        -Dsse=enabled
        -Dfft=gpl-fftw3 # try smallft
        -Dfloat-api=enabled
        -Dfixed-point=disabled
        -Dvorbis-psy=enabled
        -Db_staticpic=true
    )

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS" \
        -Dc_link_args="$LDFLAGS" \
        -Dcpp_link_args="$LDFLAGS" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local PC_FILE="$PC_DIR/speex.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i "s|^prefix=.*|prefix=$FFBUILD_PREFIX|" "$PC_FILE"
        if [[ "${PREFER_SHARED}" != "1" ]]; then
            if ! grep -q "Libs.private" "$PC_FILE"; then
                echo "Libs.private: -lm" >> "$PC_FILE"
            else
                sed -i "s/Libs.private: /Libs.private: -lm /" "$PC_FILE"
            fi
        fi
    fi
}

ffbuild_configure() {
    echo --enable-libspeex
}

ffbuild_unconfigure() {
    echo --disable-libspeex
}
