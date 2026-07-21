#!/bin/bash

SCRIPT_REPO="https://github.com/pnggroup/libpng.git"
SCRIPT_COMMIT="cae474558968f015124d7369556a4b1016276e3a"
SCRIPT_BRANCH="libpng16"

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
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # Many older packages look for libpng16.pc or libpng.pc; pixman looks for png.pc
    ln -sf libpng16.pc "$PC_DIR/libpng.pc"
    ln -sf libpng16.pc "$PC_DIR/png.pc"
}
