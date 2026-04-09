#!/bin/bash

SCRIPT_REPO="https://github.com/khronosGroup/SPIRV-Tools.git"
SCRIPT_COMMIT="2c75d08e3b31a673726ce6be80ab528250247064"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build && cd build

    local myconf=(
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_BUILD_TYPE=Release
        -DSKIP_SPIRV_TOOLS_INSTALL=OFF
        -DSPIRV_CHECK_CONTEXT=OFF
        -DSPIRV_SKIP_EXECUTABLES=ON
        -DSPIRV_SKIP_TESTS=ON
        -DSPIRV_TOOLS_BUILD_SHARED=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)F
        -DSPIRV_TOOLS_BUILD_STATIC=$([ "${PREFER_SHARED}" == "1" ] && echo OFF || echo ON)
        -DSPIRV_TOOLS_LIBRARY_TYPE=$([ "${PREFER_SHARED}" == "1" ] && echo SHARED || echo STATIC)
        -DSPIRV_WARN_EVERYTHING=OFF
        -DSPIRV_WERROR=OFF # Указываем путь к уже собранным spirv-headers
        -DSPIRV-Headers_SOURCE_DIR="$FFBUILD_PREFIX"
    )

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # Удаляем ненужный .pc файл
    rm -f "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/SPIRV-Tools-shared.pc" || true
}

