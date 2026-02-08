#!/bin/bash

SCRIPT_REPO="https://github.com/TimothyGu/libilbc"
SCRIPT_COMMIT="6adb26d4a4e159cd66d4b4c5e411cd3de0ab6b5e"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    git submodule update --init

    mkdir build && cd build

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON .. -G Ninja
    ninja -j$(nproc)
    DESTDIR="$FFBUILD_DESTDIR" ninja install
}

ffbuild_configure() {
    echo --enable-libilbc
}

ffbuild_unconfigure() {
    echo --disable-libilbc
}
