#!/bin/bash
SCRIPT_REPO="https://github.com/lensfun/lensfun.git"
SCRIPT_COMMIT="9e9e4e85c516a1b8e6355a1fc04e5ea9bcbbc83e"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
# Определяем цвета и символы
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color (сброс цвета)
CHECK_MARK='✅'
CROSS_MARK='❌'

    # Применяем патчи, если они есть в папке patches/aom (как в оригинале)
    # В новом формате generate.sh папка монтируется в /builder/patches
    if [[ -d "/builder/patches/liblensfun" ]]; then
        for patch in /builder/patches/liblensfun/*.patch; do
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
    mkdir build && cd build

    # Нам нужно принудительно сказать lensfun, что glib статический
    export CFLAGS="$CFLAGS -DGLIB_STATIC_COMPILATION"
    export CXXFLAGS="$CXXFLAGS -DGLIB_STATIC_COMPILATION"

    cmake \
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
        -DBUILD_STATIC=ON \
        -DBUILD_TESTS=OFF \
        -DBUILD_LENSTOOL=OFF \
        -DBUILD_DOC=OFF \
        -DINSTALL_HELPER_SCRIPTS=OFF \
        -DBUILD_FOR_SSE=ON \
        -DBUILD_FOR_SSE2=ON \
        ..

    make -j$(nproc) V=1
    make install DESTDIR="$FFBUILD_DESTDIR"

    # В lensfun.pc часто не хватает зависимости от glib-2.0 при статической сборке
    if ! grep -q "glib-2.0" "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/lensfun.pc"; then
        sed -i 's/Requires:/Requires: glib-2.0 /' "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/lensfun.pc"
    fi
}

ffbuild_configure() {
    echo --enable-liblensfun
}

ffbuild_unconfigure() {
    echo --disable-liblensfun
}

# Добавляем флаг статики для всех последующих стадий, использующих lensfun
ffbuild_cflags() {
    echo "-DGLIB_STATIC_COMPILATION"
}
ffbuild_cxxflags() {
    echo "-DGLIB_STATIC_COMPILATION"
}
