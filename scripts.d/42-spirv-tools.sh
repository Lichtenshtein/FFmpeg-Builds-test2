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

    # Заменяем упоминание shared.pc на обычный .pc во всех DEPENDS и установках
    # Это сохранит синтаксис скобок, но заставит CMake делать одно и то же дважды
    sed -i 's/SPIRV-Tools-shared.pc/SPIRV-Tools.pc/g' CMakeLists.txt

    # Ослепляем установку целей shared в source/CMakeLists.txt
    # Просто комментируем строки, где есть упоминание shared библиотек
    if [ -f "source/CMakeLists.txt" ]; then
        sed -i 's/.*-shared.*/# \0/g' source/CMakeLists.txt
    fi

    # Убираем экспорт shared целей из основного конфига (чтобы не ломать glslang)
    # Заменяем имя цели на статическую, чтобы не было ошибки "target not found"
    find . -name "*.cmake" -exec sed -i 's/SPIRV-Tools-shared/SPIRV-Tools/g' {} +
    find . -name "CMakeLists.txt" -exec sed -i 's/SPIRV-Tools-shared/SPIRV-Tools/g' {} +

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

