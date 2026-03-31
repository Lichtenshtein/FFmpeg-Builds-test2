#!/bin/bash

SCRIPT_REPO="https://github.com/KhronosGroup/glslang.git"
SCRIPT_COMMIT="022de31e7ffa5230068858d9e6cd85ae11170bda"

ffbuild_depends() {
    echo vulkan-headers
    echo vulkan-loader
}

ffbuild_enabled() {
    return 1
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    mkdir build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DBUILD_SHARED_LIBS=OFF
        -DALLOW_EXTERNAL_SPIRV_TOOLS=ON # OFF=ЗАПРЕЩАЕМ искать внешние SPIRV-Tools
        -DGLSLANG_TESTS=OFF
        -DGLSLANG_ENABLE_INSTALL=ON
        -DENABLE_GLSLANG_BINARIES=OFF
        -DENABLE_HLSL=ON
        -DENABLE_PCH=OFF # Enables Precompiled header; try ON
        -DENABLE_SPIRV=ON
        -DENABLE_GLSLANG_JS=OFF
        -DENABLE_RTTI=ON
        -DENABLE_OPT=ON # OFF; оптимизатор, который требует SPIRV-Tools
    )

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake "${myconf[@]}" .. || return 1
    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    # Исправление для корректной линковки в FFmpeg (иногда CMake не копирует все хедеры)
    cp -r ../glslang/Public "$FFBUILD_DESTPREFIX/include/glslang"

    mkdir -p "$PC_DIR"
    cat >"$PC_DIR/glslang.pc" <<EOF
prefix=/your/prefix
libdir=${prefix}/lib
includedir=${prefix}/include

Name: glslang
Description: glslang library
Version: 11.0.0
Libs: -L${libdir} -lglslang -lMachineIndependent -lGenericCodeGen -lOSDependent -lSPIRV -lglslang-default-resource-limits
Cflags: -I${includedir}
EOF

}

ffbuild_configure() {
    echo --enable-libglslang
}

ffbuild_unconfigure() {
    echo --disable-libglslang
}
