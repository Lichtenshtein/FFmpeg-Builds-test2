#!/bin/bash

SCRIPT_REPO="https://github.com/MartinEesmaa/SVT-JPEG-XS"
SCRIPT_COMMIT="9a68bff57de86f63a08b2c6c338835005eaa31a3"
SCRIPT_BRANCH="master-new"

ffbuild_enabled() {
    [[ $TARGET == win32 ]] && return -1
    [[ $TARGET == *arm64 ]] && return -1
    return 0
}

fixarm64=()

ffbuild_dockerbuild() {

    mkdir build1 && cd build1

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" -DBUILD_SHARED_LIBS=OFF ..
    make -j$(nproc)
    make install
}

ffbuild_configure() {
    echo --enable-libsvtjpegxs
}

ffbuild_unconfigure() {
    echo --disable-libsvtjpegxs
}
