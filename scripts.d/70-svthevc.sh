#!/bin/bash

SCRIPT_REPO="https://github.com/Brainiarc7/SVT-HEVC.git"
SCRIPT_COMMIT="ee950558a2e3d0f0e3d78365b61a8f6020bd24de"

ffbuild_enabled() {
    [[ $TARGET == win32 ]] && return 1
    [[ $TARGET == *arm64 ]] && return 1
    return 0
}

fixarm64=()

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    mkdir build1 && cd build1

    local myconf=(
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_APP=OFF
        -DENABLE_NATIVE=OFF
        -DENABLE_AVX512=$([ "${USE_AVX512}" == "1" ] && echo ON || echo OFF )
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
    )

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

}

ffbuild_configure() {
    echo --enable-libsvthevc
}

ffbuild_unconfigure() {
    echo --disable-libsvthevc
}
