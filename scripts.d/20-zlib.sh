#!/bin/bash

SCRIPT_REPO="https://github.com/zlib-ng/zlib-ng"
SCRIPT_COMMIT="0aa53126240348f8dda1cfdb5ea2df1c951e8d3d"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
}

ffbuild_dockerbuild() {
    # Для zlib-ng используем cmake, чтобы он правильно определил AVX2
    mkdir build && cd build

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DBUILD_SHARED_LIBS=OFF \
        -DZLIB_COMPAT=ON \
        -DZLIB_ENABLE_TESTS=OFF \
        -DWITH_NATIVE_INSTRUCTIONS=OFF \
        -DCMAKE_C_FLAGS="$CFLAGS" ..

    make -j$(nproc)
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-zlib
}
