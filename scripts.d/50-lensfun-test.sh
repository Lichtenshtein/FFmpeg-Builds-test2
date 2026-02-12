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

    # if [[ -d "/builder/patches/liblensfun" ]]; then
        # for patch in /builder/patches/liblensfun/*.patch; do
            # echo -e "\n-----------------------------------"
            # echo "~~~ APPLYING PATCH: $patch"
            # if patch -p1 < "$patch"; then
                # echo -e "${GREEN}${CHECK_MARK} SUCCESS: Patch applied.${NC}"
                # echo "-----------------------------------"
            # else
                # echo -e "${RED}${CROSS_MARK} ERROR: PATCH FAILED! ${CROSS_MARK}${NC}"
                # echo "-----------------------------------"
                # exit 1 # если нужно прервать сборку при ошибке
            # fi
        # done
    # fi
    mkdir build && cd build

    # Явно добавляем флаги для Broadwell и статической GLib
    local mycmake=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_C_FLAGS="$CFLAGS"
        -DCMAKE_CXX_FLAGS="$CXXFLAGS"
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS"
        -DBUILD_STATIC=ON
        -DBUILD_TESTS=OFF
        -DBUILD_LENSTOOL=OFF
        -DBUILD_DOC=OFF
        # Оптимизации под CPU
        -DBUILD_FOR_SSE=ON
        -DBUILD_FOR_SSE2=ON
        -DINSTALL_HELPER_SCRIPTS=OFF
        # Помогаем найти GLib
        -DGLIB2_LIBRARIES="$FFBUILD_PREFIX/lib/libglib-2.0.a"
        -DGLIB2_INCLUDE_DIRS="$FFBUILD_PREFIX/include/glib-2.0"
    )

    cmake "${mycmake[@]}" ..
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Исправляем lensfun.pc для статической линковки FFmpeg
    # Добавляем также -lws2_32 и прочие, так как lensfun тянет glib
    local pc_file="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/lensfun.pc"
    if [[ -f "$pc_file" ]]; then
        sed -i 's/Libs: /Libs: -L${libdir} -llensfun -lstdc++ /' "$pc_file"
        if ! grep -q "glib-2.0" "$pc_file"; then
            sed -i '/^Requires:/ s/$/ glib-2.0/' "$pc_file"
        fi
    fi
}

ffbuild_configure() { echo --enable-liblensfun; }
ffbuild_unconfigure() { echo --disable-liblensfun; }

ffbuild_cflags() { echo "-DGLIB_STATIC_COMPILATION -mms-bitfields"; }
ffbuild_cxxflags() { echo "-DGLIB_STATIC_COMPILATION -mms-bitfields"; }
