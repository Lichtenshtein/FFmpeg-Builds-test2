#!/bin/bash

# SCRIPT_REPO="https://github.com/breakfastquay/rubberband.git"
# SCRIPT_COMMIT="e4296ac80b1170018a110bc326fd0d45a0eb27d6"

SCRIPT_REPO="https://github.com/pwnified/rubberband.git"
SCRIPT_COMMIT="1928d99f31536a28a485a9c90bb82ed942fa7049"

ffbuild_depends() {
    echo base
    echo fftw3
    echo libsamplerate
    echo speex
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

    mkdir -p build && cd build

    local myconf=(
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false)
        --prefix="$FFBUILD_PREFIX"
        --cross-file="$FFBUILD_MESON_CROSS"
        -Ddefault_library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        -Dcpp_std=gnu++20
        -Dc_std=gnu17
        -Dfft=fftw
        -Dtests=disabled
        -Dresampler=libsamplerate # speex or libsamplerate
    )

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        -Dc_link_args="$LDFLAGS ${USELTO}" \
        -Dcpp_link_args="$LDFLAGS ${USELTO}" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    sed -i "s|^Cflags:.*|& -I${includedir}/rubberband|" "$PC_DIR/rubberband.pc"
}

ffbuild_configure() {
    echo --enable-librubberband
}

ffbuild_unconfigure() {
    echo --disable-librubberband
}
