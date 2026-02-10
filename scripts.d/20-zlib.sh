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
    unset CC CXX LD AR AS NM RANLIB
    # Очищаем переменные, чтобы CMake не пытался использовать хостовые флаги
    # Но оставляем CFLAGS/CXXFLAGS, которые мы настроили для Broadwell
    local ORIG_CFLAGS="$CFLAGS"
    local ORIG_CXXFLAGS="$CXXFLAGS"

    mkdir build && cd build

    cmake -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DBUILD_SHARED_LIBS=OFF \
        -DZLIB_COMPAT=ON \
        -DZLIB_ENABLE_TESTS=OFF \
        -DWITH_NATIVE_INSTRUCTIONS=OFF \
        -DWITH_AVX512=OFF \
        -DWITH_AVX512VNNI=OFF \
        -DWITH_VPCLMULQDQ=OFF \
        -DCMAKE_C_FLAGS="$ORIG_CFLAGS" \
        ..

    ninja -j$(nproc)
    DESTDIR="$FFBUILD_DESTDIR" ninja install
}

ffbuild_configure() {
    echo --enable-zlib
}
