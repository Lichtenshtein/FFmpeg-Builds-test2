#!/bin/bash

SCRIPT_REPO="https://github.com/pnggroup/libpng.git"
SCRIPT_COMMIT="99652c99876997c701b9113ce509e2eb7707b9d2"
SCRIPT_BRANCH="libpng16"

ffbuild_depends() {
    echo base
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
        -DPNG_TESTS=OFF
        -DPNG_FRAMEWORK=OFF
        -DPNG_TOOLS=OFF
        -DPNG_HARDWARE_OPTIMIZATIONS=ON # enable target hardware optimizations
        -Dld-version-script=ON # enable linker version script
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( -DPNG_SHARED=ON -DPNG_STATIC=OFF ) || \
        myconf+=( -DPNG_SHARED=OFF -DPNG_STATIC=ON )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # Многие старые пакеты ищут libpng16.pc или libpng.pc; pixman looks for png.pc
    ln -sf libpng16.pc "$PC_DIR/libpng.pc"
    ln -sf libpng16.pc "$PC_DIR/png.pc"
}
