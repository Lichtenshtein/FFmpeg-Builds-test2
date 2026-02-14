#!/bin/bash

SCRIPT_REPO="https://svn.code.sf.net/p/lame/svn/trunk/lame"
SCRIPT_REV="6531"

ffbuild_depends() {
    echo base
    echo libiconv
}

ffbuild_enabled() {
    return 0
}

# ffbuild_dockerdl() {
    # echo "retry-tool sh -c \"rm -rf lame && svn checkout '${SCRIPT_REPO}@${SCRIPT_REV}' lame\" && cd lame"
# }

ffbuild_dockerdl() {
    echo "retry-tool svn checkout '${SCRIPT_REPO}@${SCRIPT_REV}' ."
}

ffbuild_dockerbuild() {
# Определяем цвета и символы
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color (сброс цвета)
CHECK_MARK='✅'
CROSS_MARK='❌'
    
    if [[ -d "/builder/patches/libmp3lame" ]]; then
        for patch in /builder/patches/libmp3lame/*.patch; do
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

    # Принудительно чиним конфиг для современных систем
    sed -i 's/AC_PREREQ(2.69)/AC_PREREQ(2.71)/' configure.in || true
    
    # Исправляем баг в Makefile, который может пытаться собрать документацию
    sed -i 's/SUBDIRS = mpglib libmp3lame frontend include doc dev/SUBDIRS = mpglib libmp3lame include/' Makefile.am

    autoreconf -fi

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-shared
        --enable-static
        --enable-nasm
        --disable-gtktest
        --disable-frontend
    )

    # export CFLAGS="$CFLAGS -DNDEBUG -D_ALLOW_INTERNAL_OPTIONS -Wno-error=incompatible-pointer-types"
    # GCC 14 требует более мягких проверок для старого кода LAME
    export CFLAGS="$CFLAGS -O3 -ffast-math -Wno-implicit-function-declaration -Wno-int-conversion -Wno-error=incompatible-pointer-types"

    ./configure "${myconf[@]}"
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-libmp3lame
}

ffbuild_unconfigure() {
    echo --disable-libmp3lame
}
