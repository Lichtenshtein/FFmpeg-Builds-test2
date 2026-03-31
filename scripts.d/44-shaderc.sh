#!/bin/bash

# SCRIPT_REPO="https://github.com/stenzek/shaderc.git"
# SCRIPT_COMMIT="d72697bfc353b547efc58421ad54ac0345441bf4"

SCRIPT_REPO="https://github.com/google/shaderc.git"
SCRIPT_COMMIT="42c364eb27982ecfc9e00e384df205730e65b90c"

export SKIP_PRE_PATCH=1

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

    # Важно: Shaderc очень капризен к путям. Используем полные пути к third_party.
    local myconf=(
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DSHADERC_GLSLANG_DIR="$(realpath ../third_party/glslang)"
        -DSHADERC_SPIRV_TOOLS_DIR="$(realpath ../third_party/spirv-tools)"
        -DSHADERC_SPIRV_HEADERS_DIR="$(realpath ../third_party/spirv-headers)"
        -DBUILD_SHARED_LIBS=OFF
        -DSHADERC_ENABLE_SHARED_CRT=OFF
        -DSHADERC_ENABLE_WERROR_COMPILE=OFF
        -DSHADERC_SKIP_TESTS=ON
        -DSHADERC_SKIP_EXAMPLES=ON
        -DSHADERC_SKIP_COPYRIGHT_CHECK=ON
        -DSHADERC_ENABLE_COMBINED_STATIC=ON
        -DENABLE_GLSLANG_BINARIES=OFF
        -DSPIRV_SKIP_EXECUTABLES=ON
    )

    cmake -GNinja "${myconf[@]}" .. || return 1
    ninja install || return 1

    # Shaderc часто "забывает" скопировать libshaderc_combined.a или util
    cp -v libshaderc/libshaderc_combined.a "$FFBUILD_PREFIX/lib/"
    cp -v libshaderc_util/libshaderc_util.a "$FFBUILD_PREFIX/lib/"

    # РУЧНОЕ СОЗДАНИЕ PKG-CONFIG (Самый важный этап для FFmpeg)
    # FFmpeg будет искать shaderc.pc. Мы заставим его линковать всё сразу.
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

    # STAGE 2: NATIVE GLSLC (Fixing the unknown target error)
    (
        log_info "Building native glslc..."
        unset CC CXX CFLAGS CXXFLAGS LDFLAGS LIBS PKG_CONFIG_LIBDIR PKG_CONFIG_PATH
        mkdir ../native_build && cd ../native_build
        # Для нативной сборки нам не нужен весь стек, только сам компилятор
        cmake -GNinja -DCMAKE_BUILD_TYPE=Release -DSHADERC_SKIP_TESTS=ON -DSHADERC_SKIP_EXAMPLES=ON ..
        ninja glslc
        cp -v glslc/glslc /opt/glslc || cp -v glslc /opt/glslc
    )

}

ffbuild_configure() {
    echo --enable-libshaderc
}

ffbuild_unconfigure() {
    echo --disable-libshaderc
}
