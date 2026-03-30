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

    # Удаляем генерацию и установку shared.pc
    sed -i '/add_custom_command(OUTPUT.*SPIRV-Tools-shared.pc/,/DEPENDS.*SPIRV-Tools-shared.pc.in/d' CMakeLists.txt
    sed -i 's/DEPENDS.*SPIRV-Tools-shared.pc/DEPENDS/g' CMakeLists.txt
    sed -i '/SPIRV-Tools-shared.pc/d' CMakeLists.txt

    # запрещаем экспорт цели SPIRV-Tools-shared в CMake-конфиги
    # Ищем строки установки и вырезаем те, что относятся к shared
    sed -i '/SPIRV-Tools-shared/d' source/CMakeLists.txt

    # Отключаем само создание shared библиотеки в основном файле, если оно там есть
    sed -i '/add_library(SPIRV-Tools-shared/d' source/CMakeLists.txt

    mkdir build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DBUILD_SHARED_LIBS=OFF
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

