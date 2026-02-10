#!/bin/bash

SCRIPT_REPO="https://gitlab.com/damian101/aom-psy101.git"
SCRIPT_COMMIT="6a3435223b36b29e6cc9815b1f86720dcaba57f6" 

ffbuild_depends() {
    echo vmaf
    echo zlib
}

ffbuild_enabled() {
    [[ $VARIANT == lgpl* ]] && return -1
    [[ $TARGET == winarm64 ]] && return -1
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
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
    if [[ -d "/builder/patches/aom" ]]; then
        for patch in /builder/patches/aom/*.patch; do
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

    mkdir cmbuild && cd cmbuild

    # Пробрасываем пути к VMAF, как в оригинальном скрипте
    # Это лечит проблемы поиска заголовков при сборке самого AOM
    export CFLAGS="$CFLAGS -pthread -I/opt/ffbuild/include/libvmaf"

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_C_FLAGS="$CFLAGS"
        -DCMAKE_CXX_FLAGS="$CXXFLAGS"
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=OFF
        -DENABLE_EXAMPLES=NO
        -DENABLE_TESTS=NO
        -DENABLE_DOCS=NO
        -DENABLE_TOOLS=NO
        -DENABLE_CCACHE=ON
        -DCONFIG_TUNE_VMAF=1
        -DCONFIG_AV1_DECODER=ON
        -DENABLE_NASM=ON
    )

    cmake "${myconf[@]}" ..
    make -j$(nproc) V=1
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Добавляем VMAF в pkg-config, иначе FFmpeg не соберется статикой
    echo "Requires.private: libvmaf" >> "$FFBUILD_DESTPREFIX"/lib/pkgconfig/aom.pc
}

ffbuild_configure() {
    echo --enable-libaom
}

ffbuild_unconfigure() {
    echo --disable-libaom
}
