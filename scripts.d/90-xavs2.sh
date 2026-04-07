#!/bin/bash

SCRIPT_REPO="https://github.com/pkuvcl/xavs2.git"
SCRIPT_COMMIT="eae1e8b9d12468059bdd7dee893508e470fa83d8"

ffbuild_depends() {
    echo avisynth
}

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
    set -e
    # Фикс для современных компиляторов (json11)
    # Ищем файл во всем дереве, так как путь может варьироваться
    find . -name "json11.cpp" -exec sed -i '1i#include <cstdint>' {} +

    cd build/linux

    # Фикс проверки endianness
    sed -i -e 's/EGIB/bss/g' -e 's/naidnePF/bss/g' configure

    local myconf=(
        --disable-cli
        --enable-pic
        --enable-strip
        --bit-depth=10
        --chroma-format=all
        # --disable-avs
        --disable-swscale
        --disable-lavf
        --disable-ffms
        --disable-gpac
        --disable-lsmash
        --extra-asflags="-w-macro-params-legacy"
        --prefix="$FFBUILD_PREFIX"
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )
    [[ "$USE_LTO" == "1" ]] && myconf+=( --enable-lto )

    if [[ $TARGET == win* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
            --cross-prefix="$FFBUILD_CROSS_PREFIX"
        )
        # Явно указываем ассемблер, чтобы не пропустить оптимизации
        export AS="nasm"
    fi

    ./configure "${myconf[@]}" \
        --extra-cflags="$CFLAGS $CPPFLAGS" \
        --extra-ldflags="$LDFLAGS" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    # Проверка и фикс pkg-config
    # xavs2 иногда пишет неверные пути в .pc файл при использовании DESTDIR
    if [[ -f "$PC_DIR/xavs2.pc" ]]; then
        sed -i "s|^prefix=.*|prefix=$FFBUILD_PREFIX|" "$PC_DIR/xavs2.pc"
        # Для статической линковки в FFmpeg
        echo "Libs.private: -lstdc++ -lm" >> "$PC_DIR/xavs2.pc"
    fi

}

ffbuild_configure() {
    echo --enable-libxavs2
}

ffbuild_unconfigure() {
    echo --disable-libxavs2
}
