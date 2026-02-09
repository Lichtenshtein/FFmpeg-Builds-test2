#!/bin/bash

# Используем R73 (релизный тег)
SCRIPT_REPO="https://github.com/vapoursynth/vapoursynth.git"
SCRIPT_COMMIT="877a177e6f9f6e654973e0b611f571901509fb12"

ffbuild_depends() {
    # Vapoursynth сильно зависит от zimg
    echo zlib
    echo zimg
}

ffbuild_enabled() {
    # Vapoursynth обычно не собирают под x86 (32-bit) из-за лимитов памяти
    [[ $TARGET == win32 ]] && return -1
    return 0
}

ffbuild_dockerdl() {
    # Клонируем тег R73 прямо в корень
    echo "git clone --filter=blob:none --depth 1 --branch \"$SCRIPT_COMMIT\" \"$SCRIPT_REPO\" ."
}

ffbuild_dockerbuild() {
    # Vapoursynth требует автогенерации скриптов сборки
    ./autogen.sh

    # Настройка параметров для Win64
    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --enable-static
        --disable-shared
        --disable-vsscript
        --disable-python-module
        --disable-core
        --disable-plugins
    )

    # Для FFmpeg нам нужны только хедеры и интерфейс линковки (VSRuntime)
    # Если вам нужен полный Core внутри FFmpeg, настройки будут сложнее
    
    ./configure "${myconf[@]}" \
        CFLAGS="$CFLAGS" \
        CXXFLAGS="$CXXFLAGS" \
        LDFLAGS="$LDFLAGS"

    make -j$(nproc)
    make install DESTDIR="$FFBUILD_DESTDIR"

    # FFmpeg ищет Vapoursynth через pkg-config
    # Исправляем путь в .pc файле, если он криво сгенерировался
    sed -i "s|prefix=.*|prefix=$FFBUILD_PREFIX|" "$FFBUILD_DESTPREFIX"/lib/pkgconfig/vapoursynth.pc
}

ffbuild_configure() {
    echo --enable-vapoursynth
}

ffbuild_unconfigure() {
    echo --disable-vapoursynth
}
