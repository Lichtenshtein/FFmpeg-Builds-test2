#!/bin/bash

SCRIPT_REPO="https://github.com/mpeg5/xeve.git"
SCRIPT_COMMIT="bc45faa2e8d22bf33b0d15c025662f2a8de61fbc"

ffbuild_enabled() {
    [[ $TARGET == *arm64 ]] && return -1
    return 0
}

ffbuild_dockerbuild() {

    if [ ! -f "version.txt" ]; then
        echo v0.5.1 >> version.txt
    fi
    
    mkdir build && cd build

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" ..
    make -j$(nproc)
    make install DESTDIR="$FFBUILD_DESTDIR"

    mv "$FFBUILD_DESTPREFIX"/lib/xeve/libxeve.a "$FFBUILD_DESTPREFIX"/lib
    
    if [[ $TARGET == win* ]]; then
        rm "$FFBUILD_DESTPREFIX"/bin/libxeve.dll
        rm "$FFBUILD_DESTPREFIX"/lib/libxeve.dll.a
    elif [[ $TARGET == linux* ]]; then
        rm "$FFBUILD_DESTPREFIX"/lib/libxeve.so*
    fi
}

ffbuild_configure() {
    echo --enable-libxeve
}

ffbuild_unconfigure() {
    (( $(ffbuild_ffver) > 601 )) || return 0
    echo --disable-libxeve
}