#!/bin/bash

SCRIPT_REPO="https://github.com/KhronosGroup/SPIRV-Cross.git"
SCRIPT_COMMIT="146679ff8255a6068518685599d7fb8761d1b570"

ffbuild_depends() {
    echo vulkan-headers
    echo vulkan-loader
    echo glslang
    echo shaderc
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    VER_MAJ="$(grep 'set(spirv-cross-abi-major' CMakeLists.txt | sed -re 's/.* ([0-9]+)\)/\1/')"
    VER_MIN="$(grep 'set(spirv-cross-abi-minor' CMakeLists.txt | sed -re 's/.* ([0-9]+)\)/\1/')"
    VER_PCH="$(grep 'set(spirv-cross-abi-patch' CMakeLists.txt | sed -re 's/.* ([0-9]+)\)/\1/')"
    VER_FULL="$VER_MAJ.$VER_MIN.$VER_PCH"

    mkdir -p build && cd build

    local myconf=(
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DSPIRV_CROSS_SHARED=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DSPIRV_CROSS_STATIC=$([ "${PREFER_SHARED}" == "1" ] && echo OFF || echo ON)
        -DSPIRV_CROSS_CLI=OFF
        -DSPIRV_CROSS_ENABLE_TESTS=OFF
        -DSPIRV_CROSS_FORCE_PIC=ON
        -DSPIRV_CROSS_ENABLE_C_API=ON
        -DSPIRV_CROSS_ENABLE_CPP=ON
    )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    cat >"$PC_DIR/spirv-cross-c-shared.pc" <<EOF
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${prefix}/lib
sharedlibdir=\${prefix}/lib
includedir=\${prefix}/include

Name: spirv-cross-c-shared
Description: C API for SPIRV-Cross
Version: ${VER_FULL}

Requires:
Libs: -L\${libdir} -L\${sharedlibdir} -lspirv-cross-c -lspirv-cross-glsl -lspirv-cross-hlsl -lspirv-cross-reflect -lspirv-cross-msl -lspirv-cross-util -lspirv-cross-core -lstdc++
Cflags: -I\${includedir} -I\${includedir}/spirv_cross
EOF

    sed -i "s|^Cflags:.*|& -I\${includedir}/spirv_cross|" "$PC_DIR/spirv-cross-c.pc"
}
