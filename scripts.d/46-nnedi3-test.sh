#!/bin/bash

SCRIPT_REPO="https://github.com/Jamaika1/AviSynthPlus-NNEDI3CL.git"
SCRIPT_COMMIT="patch-1"

ffbuild_enabled() {
    # Этот фильтр требует OpenCL (45-opencl.sh)
    return 0
}

ffbuild_dockerdl() {
    echo "git clone --filter=blob:none --branch \"$SCRIPT_COMMIT\" \"$SCRIPT_REPO\" ."
}

ffbuild_dockerdl() {
    default_dl .
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
