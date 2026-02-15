#!/bin/bash

SCRIPT_REPO="https://github.com/Jamaika1/AviSynthPlus-NNEDI3CL.git"
SCRIPT_COMMIT="ae51fe937f44bfa8e9099a52f39897c1f181a80a"
SCRIPT_BRANCH="patch-1"

ffbuild_enabled() {
    # Этот фильтр требует OpenCL (45-opencl.sh)
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
}

ffbuild_dockerbuild() {
    mkdir build && cd build

    cmake -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF ..
    
    ninja -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja install
}
