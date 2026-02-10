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
    # Уходим в корень сборки этапа, чтобы сбросить любые cd из предыдущих скриптов
    cd "/build/$STAGENAME"

    # Сброс инструментов для чистоты CMake
    # unset CC CXX LD AR AS NM RANLIB
    
    mkdir -p build_zlib
    cd build_zlib

    # Используем абсолютный путь к исходникам (..)
    cmake -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DZLIB_COMPAT=ON \
        -DZLIB_ENABLE_TESTS=OFF \
        -DWITH_NATIVE_INSTRUCTIONS=OFF \
        -DWITH_AVX512=OFF \
        -DWITH_AVX512VNNI=OFF \
        -DWITH_VPCLMULQDQ=OFF \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        ..

    # Проверяем, создался ли файл перед запуском
    if [[ ! -f "build.ninja" ]]; then
        echo "ERROR: CMake failed to generate build.ninja"
        exit 1
    fi

    ninja -j$(nproc)
    DESTDIR="$FFBUILD_DESTDIR" ninja install
}

ffbuild_configure() {
    echo --enable-zlib
}
