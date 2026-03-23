#!/bin/bash

SCRIPT_REPO="https://github.com/libgme/game-music-emu.git"
SCRIPT_COMMIT="bb58c4a9a9ba847fc8f423aec8ffe9eb957baadf"

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
    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DCMAKE_DISABLE_FIND_PACKAGE_SDL2=1 \
        -DBUILD_SHARED_LIBS=OFF \
        -DGME_BUILD_STATIC=ON \
        -DGME_BUILD_FRAMEWORK=OFF \
        -DGME_BUILD_TESTING=OFF \
        -DGME_BUILD_EXAMPLES=OFF \
        -DGME_SPC_ISOLATED_ECHO_BUFFER=ON \
        -DGME_ZLIB=ON \
        -DENABLE_UBSAN=OFF .. || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

}

ffbuild_configure() {
    echo --enable-libgme
}

ffbuild_unconfigure() {
    echo --disable-libgme
}
