#!/bin/bash

SCRIPT_REPO="https://github.com/fraunhoferhhi/vvenc"
SCRIPT_COMMIT="7fcb538e613dd36408363b4fd1ab6dc99c664058"

ffbuild_enabled() {
    return 0
}

fixarm64=()

ffbuild_dockerbuild() {

    mkdir build && cd build

    if [[ $TARGET == *arm64 ]]; then
    fixarm64=(
        -DVVENC_ENABLE_X86_SIMD=OFF 
        -DVVENC_ENABLE_ARM_SIMD=OFF
    )
    fi

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF -DVVENC_LIBRARY_ONLY=ON -DVVENC_ENABLE_LINK_TIME_OPT=OFF -DEXTRALIBS="-lstdc++" "${fixarm64[@]}" ..

    make -j$(nproc)
    make install
}

ffbuild_configure() {
    echo --enable-libvvenc
}

ffbuild_unconfigure() {
    (( $(ffbuild_ffver) > 700 )) || return 0
    echo --disable-libvvenc
}
