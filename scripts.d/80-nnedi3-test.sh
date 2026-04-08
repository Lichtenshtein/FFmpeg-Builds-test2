#!/bin/bash

SCRIPT_REPO="https://github.com/Asd-g/AviSynthPlus-NNEDI3CL.git"
SCRIPT_COMMIT="bd454d1e9fea7c9f7e059f4e6abe17e67f0935d8"

# SCRIPT_REPO="https://github.com/Jamaika1/AviSynthPlus-NNEDI3CL.git"
# SCRIPT_COMMIT="ae51fe937f44bfa8e9099a52f39897c1f181a80a"
# SCRIPT_BRANCH="patch-1"

ffbuild_depends() {
    # Этот фильтр требует OpenCL (opencl.sh)
    echo avisynth
    echo opencl
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-submodule-clone"
}

ffbuild_dockerbuild() {
    set -e

    mkdir build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DUSE_SYSTEM_AVS_HELPER=OFF # Use an installed version of avs_c_api_loader
    )

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1
}
