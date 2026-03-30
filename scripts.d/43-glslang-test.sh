#!/bin/bash

SCRIPT_REPO="https://github.com/KhronosGroup/glslang.git"
SCRIPT_COMMIT="022de31e7ffa5230068858d9e6cd85ae11170bda"

ffbuild_depends() {
    echo vulkan-headers
    echo vulkan-loader
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    mkdir build && cd build

    local mycmake=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DBUILD_SHARED_LIBS=OFF
        -DALLOW_EXTERNAL_SPIRV_TOOLS=OFF # ЗАПРЕЩАЕМ искать внешние SPIRV-Tools
        -DGLSLANG_TESTS=OFF
        -DGLSLANG_ENABLE_INSTALL=ON
        -DENABLE_GLSLANG_BINARIES=OFF
        -DENABLE_PCH=OFF # Enables Precompiled header; try ON
        -DENABLE_CTEST=OFF
        -DENABLE_SPIRV=ON
        -DENABLE_GLSLANG_JS=OFF
        -DENABLE_RTTI=ON
        -DENABLE_OPT=ON # оптимизатор, который требует SPIRV-Tools
    )

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake "${mycmake[@]}" .. || return 1
    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    # Исправление для корректной линковки в FFmpeg (иногда CMake не копирует все хедеры)
    cp -r ../glslang/Public "$FFBUILD_DESTPREFIX/include/glslang"

}

ffbuild_configure() {
    echo --enable-libglslang
}

ffbuild_unconfigure() {
    echo --disable-libglslang
}
