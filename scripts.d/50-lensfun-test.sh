#!/bin/bash
SCRIPT_REPO="https://github.com/lensfun/lensfun.git"
SCRIPT_COMMIT="9e9e4e85c516a1b8e6355a1fc04e5ea9bcbbc83e"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    # Изменить 'v1' на 'v2', чтобы сбросить кэш загрузки
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" . && echo 'v2-meson-upgrade'"
}

ffbuild_dockerbuild() {
# Определяем цвета и символы
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color (сброс цвета)
CHECK_MARK='✅'
CROSS_MARK='❌'

    if [[ -d "/builder/patches/liblensfun" ]]; then
        for patch in /builder/patches/liblensfun/*.patch; do
            echo -e "\n-----------------------------------"
            echo "~~~ APPLYING PATCH: $patch"
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
    python3 -m pip install build

    mkdir build && cd build

    # нужно передать ДВА пути к инклудам Glib
    local GLIB_INCLUDES="-I$FFBUILD_PREFIX/include/glib-2.0 -I$FFBUILD_PREFIX/lib/glib-2.0/include"

    local mycmake=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        # Добавляем пути к glibconfig.h через C_FLAGS
        -DCMAKE_C_FLAGS="$CFLAGS $GLIB_INCLUDES"
        -DCMAKE_CXX_FLAGS="$CXXFLAGS $GLIB_INCLUDES"
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS"
        -DBUILD_STATIC=ON
        -DBUILD_TESTS=OFF
        -DBUILD_LENSTOOL=OFF
        -DBUILD_DOC=OFF
        -DBUILD_FOR_SSE=ON
        -DBUILD_FOR_SSE2=ON
        -DINSTALL_HELPER_SCRIPTS=OFF
        # Отключаем Python принудительно
        -DPYTHON_EXECUTABLE=OFF
        # Уточняем пути для CMake-модуля поиска Glib
        -DGLIB2_LIBRARIES="$FFBUILD_PREFIX/lib/libglib-2.0.a"
        -DGLIB2_BASE_INCLUDE_DIR="$FFBUILD_PREFIX/include/glib-2.0"
        -DGLIB2_INTERNAL_INCLUDE_DIR="$FFBUILD_PREFIX/lib/glib-2.0/include"
    )

    cmake "${mycmake[@]}" ..
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Исправляем .pc файл
    local pc_file="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/lensfun.pc"
    if [[ -f "$pc_file" ]]; then
        # Добавляем путь к glibconfig.h в Cflags .pc файла
        sed -i "s|Cflags: |Cflags: -I${FFBUILD_PREFIX}/lib/glib-2.0/include |" "$pc_file"
        if ! grep -q "glib-2.0" "$pc_file"; then
            sed -i '/^Requires:/ s/$/ glib-2.0/' "$pc_file"
        fi
    fi
}

ffbuild_configure() { echo --enable-liblensfun; }
ffbuild_unconfigure() { echo --disable-liblensfun; }

# прокидываем пути для всех последующих стадий
ffbuild_cflags() { echo "-I$FFBUILD_PREFIX/lib/glib-2.0/include -DGLIB_STATIC_COMPILATION -mms-bitfields"; }
ffbuild_cxxflags() { echo "-I$FFBUILD_PREFIX/lib/glib-2.0/include -DGLIB_STATIC_COMPILATION -mms-bitfields"; }