#!/bin/bash

SCRIPT_REPO="https://github.com/zlib-ng/zlib-ng.git"
SCRIPT_COMMIT="d225a913909176588060c2d5eb1d58bacd11c8c8"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
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
        -DBUILD_TESTING=OFF \
        -DWITH_NEW_STRATEGIES=ON \
        -DWITH_CRC32_CHORBA=ON \
        -DWITH_NATIVE_INSTRUCTIONS=OFF \
        -DWITH_RUNTIME_CPU_DETECTION=ON \
        -DWITH_OPTIM=ON \
        -DWITH_SSE2=ON \
        -DWITH_SSSE3=ON \
        -DWITH_SSE41=ON \
        -DWITH_SSE42=ON \
        -DWITH_PCLMULQDQ=ON \
        -DWITH_AVX2=ON \
        -DWITH_AVX512=OFF \
        -DWITH_AVX512VNNI=OFF \
        -DWITH_VPCLMULQDQ=OFF \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        ..

    # Проверяем, создался ли файл перед запуском
    if [[ ! -f "build.ninja" ]]; then
        echo "ERROR: CMake failed to generate build.ninja"
        return 1
    fi

    ninja -j$(nproc)
    DESTDIR="$FFBUILD_DESTDIR" ninja install
}

ffbuild_cppflags() {
    echo "-DZLIB_STATIC"
}

ffbuild_configure() {
    echo --enable-zlib
}
