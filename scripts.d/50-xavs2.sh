#!/bin/bash

SCRIPT_REPO="https://github.com/pkuvcl/xavs2.git"
SCRIPT_COMMIT="eae1e8b9d12468059bdd7dee893508e470fa83d8"

ffbuild_enabled() {
    [[ $VARIANT == lgpl* ]] && return 1
    [[ $TARGET == win32 ]] && return 1
    # xavs2 aarch64 support is broken
    [[ $TARGET == *arm64 ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    if [[ -d "/builder/patches/xavs2" ]]; then
        for patch in /builder/patches/xavs2/*.patch; do
            log_info "APPLYING PATCH: $patch"
            if patch -p1 -N -r - < "$patch"; then
                log_info "${GREEN}${CHECK_MARK} SUCCESS: Patch applied.${NC}"
            else
                log_error "${RED}${CROSS_MARK} ERROR: PATCH FAILED! ${CROSS_MARK}${NC}"
                # return 1 # если нужно прервать сборку при ошибке
            fi
        done
    fi

    # Фикс для современных компиляторов (json11)
    # Ищем файл во всем дереве, так как путь может варьироваться
    find . -name "json11.cpp" -exec sed -i '1i#include <cstdint>' {} +

    cd build/linux

    # Фикс проверки endianness
    sed -i -e 's/EGIB/bss/g' -e 's/naidnePF/bss/g' configure

    local myconf=(
        --disable-cli
        --enable-static
        --enable-pic
        --disable-avs
        --disable-swscale
        --disable-lavf
        --disable-ffms
        --disable-gpac
        --disable-lsmash
        --extra-asflags="-w-macro-params-legacy"
        --prefix="$FFBUILD_PREFIX"
    )

    if [[ $TARGET == win* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
            --cross-prefix="$FFBUILD_CROSS_PREFIX"
        )
        # Явно указываем ассемблер, чтобы не пропустить оптимизации
        export AS="nasm" 
    fi

    # Добавляем глобальные флаги через --extra-cflags
    ./configure "${myconf[@]}" --extra-cflags="$CFLAGS" --extra-ldflags="$LDFLAGS"

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Проверка и фикс pkg-config
    # xavs2 иногда пишет неверные пути в .pc файл при использовании DESTDIR
    if [[ -f "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/xavs2.pc" ]]; then
        sed -i "s|^prefix=.*|prefix=$FFBUILD_PREFIX|" "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/xavs2.pc"
        # Для статической линковки в FFmpeg
        echo "Libs.private: -lstdc++ -lm" >> "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/xavs2.pc"
    fi
}

ffbuild_configure() {
    echo --enable-libxavs2
}

ffbuild_unconfigure() {
    echo --disable-libxavs2
}
