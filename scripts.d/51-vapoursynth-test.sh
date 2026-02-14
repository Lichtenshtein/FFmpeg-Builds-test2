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
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
    # echo "git clone --filter=blob:none --depth 1 --branch \"$SCRIPT_COMMIT\" \"$SCRIPT_REPO\" ."
}

ffbuild_dockerbuild() {
    # Vapoursynth требует автогенерации скриптов сборки
    ./autogen.sh

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --enable-static
        --disable-shared
        --disable-vsscript       # Оставляем выключенным для экономии места
        --disable-python-module  # Python в статичном FFmpeg под Win64 почти невозможен
        --disable-core           # Мы используем Vapoursynth как интерфейс загрузки скриптов
    )

    # Для FFmpeg нам нужны только хедеры и интерфейс линковки (VSRuntime)
    # Если нужен полный Core внутри FFmpeg, настройки будут сложнее
    
    ./configure "${myconf[@]}" \
        CFLAGS="$CFLAGS" \
        CXXFLAGS="$CXXFLAGS" \
        LDFLAGS="$LDFLAGS"

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # FFmpeg ищет Vapoursynth через pkg-config
    # Исправляем путь в .pc файле, если он криво сгенерировался
    sed -i "s|prefix=.*|prefix=$FFBUILD_PREFIX|" "$FFBUILD_DESTPREFIX"/lib/pkgconfig/vapoursynth.pc
    # FFmpeg не увидит Vapoursynth, если не будет правильных флагов в .pc
    # Добавляем -lstdc++ и убираем динамические зависимости
    sed -i "s/Libs: .*/Libs: -L\${libdir} -lvapoursynth -lstdc++/" "$FFBUILD_DESTPREFIX"/lib/pkgconfig/vapoursynth.pc
}

ffbuild_configure() {
    echo --enable-vapoursynth
}

ffbuild_unconfigure() {
    echo --disable-vapoursynth
}
