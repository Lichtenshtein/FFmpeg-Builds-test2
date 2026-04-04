#!/bin/bash

SCRIPT_REPO="https://github.com/Jamaika1/AviSynthPlus-NNEDI3CL.git"
SCRIPT_COMMIT="ae51fe937f44bfa8e9099a52f39897c1f181a80a"
SCRIPT_BRANCH="patch-1"

ffbuild_depends() {
    # Этот фильтр требует OpenCL (45-opencl.sh)
    echo opencl
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    mkdir build && cd build

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF ) \
        -DBUILD_SHARED_LIBS=OFF .. || return 1
    
    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

}
