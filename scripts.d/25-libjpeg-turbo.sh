#!/bin/bash

SCRIPT_REPO="https://github.com/libjpeg-turbo/libjpeg-turbo.git"
SCRIPT_COMMIT="4d293d9400281045e062b6e4eb8e1ccfc89d91f8"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    mkdir build && cd build

    # На Broadwell libjpeg-turbo будет использовать AVX2 автоматически через NASM

    local myconf=(
        "Unix Makefiles"
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DENABLE_SHARED=OFF
        -DENABLE_STATIC=ON
        -DWITH_JPEG8=ON
        -DWITH_SIMD=ON
        -DWITH_TOOLS=OFF
        -DWITH_TESTS=OFF
        -DWITH_TURBOJPEG=ON
        -DWITH_CRT_DLL=OFF
        -DCMAKE_C_FLAGS="$CFLAGS"
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON )

    cmake -G "${myconf[@]}" ..

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    return 0 # Используется внутренними компонентами
}
