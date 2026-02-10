#!/bin/bash

SCRIPT_REPO="https://github.com/kcat/openal-soft.git"
SCRIPT_COMMIT="1048903a6a1445c135b3b3b9eace9e2ec6e1d2a0"

ffbuild_enabled() {
    (( $(ffbuild_ffver) > 501 )) || return -1
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
CHECK_MARK='\u2714'
CROSS_MARK='\u2718'
    
    if [[ -d "/builder/patches/libopenal" ]]; then
        for patch in /builder/patches/libopenal/*.patch; do
            echo -e "\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
            echo "~~~ APPLYING PATCH: $patch"
            
            # Выполняем патч и проверяем код выхода
            if patch -p1 < "$patch"; then
                echo -e "${GREEN}${CHECK_MARK} SUCCESS: Patch applied.${NC}"
            else
                echo -e "${RED}${CROSS_MARK} ERROR: PATCH FAILED! ${CROSS_MARK}${NC}"
                echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
                # exit 1 # если нужно прервать сборку при ошибке
            fi
            
            echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
        done
    fi

    mkdir cm_build && cd cm_build

    export CFLAGS="$CFLAGS -include stdlib.h"
    export CXXFLAGS="$CXXFLAGS -include cstdlib"

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DLIBTYPE=STATIC \
        -DALSOFT_UTILS=OFF \
        -DALSOFT_EXAMPLES=OFF  ..
    make -j$(nproc) V=1
    make install DESTDIR="$FFBUILD_DESTDIR"

    echo "Libs.private: -lstdc++" >> "$FFBUILD_DESTPREFIX"/lib/pkgconfig/openal.pc

    if [[ $TARGET == win* ]]; then
        echo "Libs.private: -lole32 -luuid" >> "$FFBUILD_DESTPREFIX"/lib/pkgconfig/openal.pc
    fi
}

ffbuild_configure() {
    echo --enable-openal
}

ffbuild_unconfigure() {
    echo --disable-openal
}
