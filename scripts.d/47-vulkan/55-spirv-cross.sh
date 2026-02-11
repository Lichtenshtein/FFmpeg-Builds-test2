#!/bin/bash

SCRIPT_REPO="https://github.com/KhronosGroup/SPIRV-Cross.git"
SCRIPT_COMMIT="28184c1e138f18c330256eeb2f56b9f9fbc53921"

ffbuild_enabled() {
    (( $(ffbuild_ffver) > 404 )) || return -1
    return 0
}

ffbuild_dockerbuild() {
# Определяем цвета и символы
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color (сброс цвета)
CHECK_MARK='✅'
CROSS_MARK='❌'
    
    if [[ -d "/builder/patches/spirv_cross" ]]; then
        for patch in /builder/patches/spirv_cross/*.patch; do
            echo -e "\n-----------------------------------"
            echo "~~~ APPLYING PATCH: $patch"
            # Выполняем патч и проверяем код выхода
            if patch -p1 < "$patch"; then
                echo -e "${GREEN}${CHECK_MARK} SUCCESS: Patch applied.${NC}"
                echo "-----------------------------------"
            else
                echo -e "${RED}${CROSS_MARK} ERROR: PATCH FAILED! ${CROSS_MARK}${NC}"
                echo "-----------------------------------"
                # exit 1 # если нужно прервать сборку при ошибке
            fi
        done
    fi

    VER_MAJ="$(grep 'set(spirv-cross-abi-major' CMakeLists.txt | sed -re 's/.* ([0-9]+)\)/\1/')"
    VER_MIN="$(grep 'set(spirv-cross-abi-minor' CMakeLists.txt | sed -re 's/.* ([0-9]+)\)/\1/')"
    VER_PCH="$(grep 'set(spirv-cross-abi-patch' CMakeLists.txt | sed -re 's/.* ([0-9]+)\)/\1/')"
    VER_FULL="$VER_MAJ.$VER_MIN.$VER_PCH"

    mkdir build && cd build

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DSPIRV_CROSS_SHARED=OFF \
        -DSPIRV_CROSS_STATIC=ON \
        -DSPIRV_CROSS_CLI=OFF \
        -DSPIRV_CROSS_ENABLE_TESTS=OFF \
        -DSPIRV_CROSS_FORCE_PIC=ON \
        -DSPIRV_CROSS_ENABLE_CPP=OFF ..
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    cat >"$FFBUILD_DESTPREFIX"/lib/pkgconfig/spirv-cross-c-shared.pc <<EOF
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${prefix}/lib
sharedlibdir=\${prefix}/lib
includedir=\${prefix}/include/spirv_cross

Name: spirv-cross-c-shared
Description: C API for SPIRV-Cross
Version: $VER_FULL

Requires:
Libs: -L\${libdir} -L\${sharedlibdir} -lspirv-cross-c -lspirv-cross-glsl -lspirv-cross-hlsl -lspirv-cross-reflect -lspirv-cross-msl -lspirv-cross-util -lspirv-cross-core -lstdc++
Cflags: -I\${includedir}
EOF
}
