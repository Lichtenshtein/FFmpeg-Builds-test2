#!/bin/bash

SCRIPT_REPO="https://github.com/xiph/speex.git"
SCRIPT_COMMIT="05895229896dc942d453446eba6f9f5ddcf95422"

ffbuild_depends() {
    echo base
    # echo fftw3
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

    mkdir -p build && cd build

    local myconf=(
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false)
        --prefix="$FFBUILD_PREFIX"
        --cross-file="$FFBUILD_MESON_CROSS"
        --buildtype=release
        -Dcpp_std=gnu++20
        -Dc_std=gnu17
        -Ddefault_library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        -Dtools=disabled
        -Dtest-binaries=disabled
        -Dsse=enabled
        -Dfft=smallft # smallft; gpl-fftw3
        -Dfloat-api=enabled
        -Dfixed-point=disabled
        -Dvorbis-psy=enabled # must be disabled if fftw3 used
        -Db_staticpic=true
    )

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        -Dc_link_args="$LDFLAGS ${USELTO}" \
        -Dcpp_link_args="$LDFLAGS ${USELTO}" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local PC_FILE="$PC_DIR/speex.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i "s|^prefix=.*|prefix=$FFBUILD_PREFIX|" "$PC_FILE"
        if [[ "${PREFER_SHARED}" != "1" ]]; then
            if ! grep -q "Libs.private" "$PC_FILE"; then
                sed -i '/^Libs.private:/ s/$/ -lm/' "$PC_FILE"
            else
                sed -i "s/Libs.private: /Libs.private: -lm /" "$PC_FILE"
            fi
        fi
        sed -i "s|^Cflags:.*|& -I\${includedir}/speex|" "$PC_FILE"
    fi
}

ffbuild_configure() {
    echo --enable-libspeex
}

ffbuild_unconfigure() {
    echo --disable-libspeex
}
