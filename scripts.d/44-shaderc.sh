#!/bin/bash

SCRIPT_REPO="https://github.com/stenzek/shaderc.git"
SCRIPT_COMMIT="d72697bfc353b547efc58421ad54ac0345441bf4"

SCRIPT_MIRROR="https://github.com/google/shaderc.git"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    # echo "./utils/git-sync-deps || exit $?"
}

ffbuild_dockerbuild() {
    set -e

    mkdir build && cd build

    local myconf=(
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DSHADERC_GLSLANG_DIR="$(realpath ../third_party/glslang)"
        -DSHADERC_SPIRV_TOOLS_DIR="$(realpath ../third_party/spirv-tools)"
        -DSHADERC_SPIRV_HEADERS_DIR="$(realpath ../third_party/spirv-headers)"
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DALLOW_EXTERNAL_SPIRV_TOOLS=ON
        -DBUILD_SHARED_LIBS=OFF
        -DENABLE_EXCEPTIONS=ON
        -DENABLE_GLSLANG_BINARIES=OFF
        -DENABLE_GLSLANG_JS=OFF
        -DENABLE_HLSL=ON
        -DENABLE_OPT=ON
        -DENABLE_PCH=OFF
        -DENABLE_RTTI=ON
        -DENABLE_SPIRV=ON
        -DGLSLANG_ENABLE_INSTALL=ON
        -DGLSLANG_TESTS=OFF
        -DSHADERC_ENABLE_SHARED_CRT=OFF
        -DSHADERC_ENABLE_WERROR_COMPILE=OFF
        -DSHADERC_ENABLE_COMBINED_STATIC=ON
        -DSHADERC_SKIP_COPYRIGHT_CHECK=ON
        -DSHADERC_SKIP_EXAMPLES=ON
        -DSHADERC_SKIP_TESTS=ON
        -DSKIP_SPIRV_TOOLS_INSTALL=OFF
        -DSPIRV_CHECK_CONTEXT=OFF
        -DSPIRV_HEADERS_ENABLE_INSTALL=ON
        -DSPIRV_HEADERS_ENABLE_TESTS=OFF
        -DSPIRV_SKIP_EXECUTABLES=ON
        -DSPIRV_SKIP_TESTS=ON
        -DSPIRV_TOOLS_BUILD_SHARED=OFF
        -DSPIRV_TOOLS_BUILD_STATIC=ON
        -DSPIRV_TOOLS_LIBRARY_TYPE=STATIC
        -DSPIRV_WARN_EVERYTHING=OFF
        -DSPIRV_WERROR=OFF
    )

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -GNinja "${myconf[@]}" .. || return 1

    ninja install || return 1

    # Shaderc часто "забывает" скопировать libshaderc_combined.a или util
    cp -v libshaderc/libshaderc_combined.a "$FFBUILD_PREFIX/lib/"
    cp -v libshaderc_util/libshaderc_util.a "$FFBUILD_PREFIX/lib/"

    mkdir -p "$FFBUILD_PREFIX/lib/pkgconfig"
    cat <<EOF > "$FFBUILD_PREFIX/lib/pkgconfig/shaderc.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: shaderc
Description: Tools and libraries for Vulkan shader compilation.
Version: 2023.7
Libs: -L\${libdir} -lshaderc_combined -lshaderc_util -lglslang -lMachineIndependent -lGenericCodeGen -lOSDependent -lSPIRV -lSPIRV-Tools-opt -lSPIRV-Tools -lstdc++ -lpthread
Cflags: -I\${includedir}
EOF

    # Копируем результат в выходную директорию
    mkdir -p "$FFBUILD_DESTDIR/opt/ffbuild/lib/pkgconfig"
    cp -r "$FFBUILD_PREFIX"/* "$FFBUILD_DESTDIR/opt/ffbuild/"

    (
        log_info "Building native glslc..."
        unset CC CXX CFLAGS CXXFLAGS LDFLAGS LIBS PKG_CONFIG_LIBDIR PKG_CONFIG_PATH
        mkdir ../native_build && cd ../native_build
        # Для нативной сборки нам не нужен весь стек, только сам компилятор
        cmake -GNinja -DCMAKE_BUILD_TYPE=Release -DSHADERC_SKIP_TESTS=ON -DSHADERC_SKIP_EXAMPLES=ON ..
        ninja $NINJA_V -j$(nproc) glslc
        cp -v glslc/glslc /opt/glslc || cp -v glslc /opt/glslc
    )

}

ffbuild_configure() {
    echo --enable-libshaderc
}

ffbuild_unconfigure() {
    echo --disable-libshaderc
}
