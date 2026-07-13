#!/bin/bash

SCRIPT_REPO="https://github.com/GerHobbelt/libspng.git"
SCRIPT_COMMIT="0273066de898a7afccb5368b69197fe056ead6b3"

ffbuild_depends() {
    echo zlib
}

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
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DSPNG_ENABLE_OPT=ON
        -SPNG_BUILD_EXAMPLES=OFF
        -SPNG_INSTALL=ON
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( -DSPNG_SHARED=ON -DSPNG_STATIC=OFF ) || \
        myconf+=( -DSPNG_SHARED=OFF -DSPNG_STATIC=ON )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1
}
