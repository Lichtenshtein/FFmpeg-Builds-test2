#!/bin/bash

SCRIPT_REPO="https://github.com/KhronosGroup/glslang.git"
SCRIPT_COMMIT="022de31e7ffa5230068858d9e6cd85ae11170bda"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    mkdir build && cd build

    local mycmake=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_C_FLAGS="$CFLAGS"
        -DCMAKE_CXX_FLAGS="$CXXFLAGS"
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS"
        -DBUILD_SHARED_LIBS=OFF
        -DENABLE_GLSLANG_BINARIES=OFF
        -DENABLE_PCH=OFF
        -DENABLE_CTEST=OFF
        -DALLOW_EXTERNAL_SPIRV_TOOLS=ON # Разрешаем искать SPIRV-Tools в системе
        -DENABLE_OPT=OFF                # Для FFmpeg оптимизатор glslang обычно не критичен, 
                                        # его отключение решает 90% проблем сборки
    )

    cmake "${mycmake[@]}" ..
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Исправление для корректной линковки в FFmpeg (иногда CMake не копирует все хедеры)
    cp -r ../glslang/Public "$FFBUILD_DESTPREFIX/include/glslang"
}

ffbuild_configure() {
    echo --enable-libglslang
}

ffbuild_unconfigure() {
    echo --disable-libglslang
}
