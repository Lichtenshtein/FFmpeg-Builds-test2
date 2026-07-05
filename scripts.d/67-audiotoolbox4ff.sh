#!/bin/bash

SCRIPT_REPO="https://github.com/chrdev/wat4ff.git"
SCRIPT_COMMIT="425afa33c966dc90fef70d732cebe2626d1a4022"

ffbuild_enabled() {
    [[ $TARGET == win* ]] && return 1
    return 1
}

ffbuild_dockerbuild() {
    mkdir build && cd build

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" ..
    make
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-audiotoolbox
}

ffbuild_unconfigure() {
    echo --disable-audiotoolbox
}
