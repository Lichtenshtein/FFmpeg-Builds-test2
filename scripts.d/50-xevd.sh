#!/bin/bash

SCRIPT_REPO="https://github.com/mpeg5/xevd"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {

    if [ ! -f "version.txt" ]; then
        echo v0.5.0 >> version.txt
    fi
    
    mkdir build && cd build

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" ..
    make -j$(nproc)
    make install

    mv "$FFBUILD_PREFIX"/lib/xevd/libxevd.a "$FFBUILD_PREFIX"/lib
    
    if [[ $TARGET == win* ]]; then
        rm "$FFBUILD_PREFIX"/bin/libxevd.dll
        rm "$FFBUILD_PREFIX"/lib/libxevd.dll.a
    elif [[ $TARGET == linux* ]]; then
        rm "$FFBUILD_PREFIX"/bin/libxevd.so*
        rm "$FFBUILD_PREFIX"/lib/libxevd.so*
    fi
}

ffbuild_configure() {
    echo --enable-libxevd
}

ffbuild_unconfigure() {
    (( $(ffbuild_ffver) > 601 )) || return 0
    echo --disable-libxevd
}