#!/bin/bash

SCRIPT_REPO="https://github.com/libjpeg-turbo/libjpeg-turbo.git"
SCRIPT_COMMIT="af9c1c268520a29adf98cad5138dafe612b3d318"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
}

ffbuild_dockerbuild() {
    mkdir build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DENABLE_SHARED=OFF
        -DENABLE_STATIC=ON
        -DWITH_JPEG8=ON
        -DWITH_CRT_DLL=OFF
    )

    # На Broadwell libjpeg-turbo будет использовать AVX2 автоматически через NASM
    cmake "${myconf[@]}" -DCMAKE_C_FLAGS="$CFLAGS" ..

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    return 0 # Используется внутренними компонентами
}
