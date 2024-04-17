#!/bin/bash

SCRIPT_REPO="https://github.com/fraunhoferhhi/vvenc"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {

    mkdir build && cd build

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" $fixarm64 ..

        if [[ $TARGET == *arm64 ]]; then
        fixarm64=(
            -DVVENC_ENABLE_X86_SIMDE=OFF
        )
        fi
    
    make -j$(nproc)
    make install
}

ffbuild_configure() {
    echo --enable-libvvenc
}

ffbuild_unconfigure() {
    echo --disable-libvvenc
}
