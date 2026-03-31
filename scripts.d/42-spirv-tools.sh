#!/bin/bash

SCRIPT_REPO="https://github.com/khronosGroup/SPIRV-Tools.git"
SCRIPT_COMMIT="2c75d08e3b31a673726ce6be80ab528250247064"

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
        -DBUILD_SHARED_LIBS=OFF
        -DSPIRV_TOOLS_BUILD_SHARED=OFF
        -DSPIRV_TOOLS_BUILD_STATIC=ON
        -DSKIP_SPIRV_TOOLS_INSTALL=OFF
        -DSPIRV_CHECK_CONTEXT=OFF
        -DSPIRV_SKIP_EXECUTABLES=ON
        -DSPIRV_SKIP_TESTS=ON
        -DSPIRV_TOOLS_BUILD_STATIC=ON
        -DSPIRV_TOOLS_LIBRARY_TYPE=STATIC
        -DSPIRV_WARN_EVERYTHING=OFF
        -DSPIRV_WERROR=OFF        # Указываем путь к уже собранным spirv-headers
        -DSPIRV-Headers_SOURCE_DIR="$FFBUILD_PREFIX"
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON )

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake "${myconf[@]}" .. || return 1
    make -j$(nproc) || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    # Удаляем ненужный .pc файл
    rm -f "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/SPIRV-Tools-shared.pc" || true

}

