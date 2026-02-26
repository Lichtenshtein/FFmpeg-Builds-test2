#!/bin/bash

SCRIPT_REPO="https://code.videolan.org/videolan/dav1d.git"
SCRIPT_COMMIT="60507bffc0b13e7a81753a51005dbbeba4b23018"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    mkdir build && cd build

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --libdir="$FFBUILD_PREFIX/lib"
        --cross-file=/cross.meson
        --buildtype=release
        --default-library=static
        -Denable_asm=true
        -Denable_tools=false
        -Denable_tests=false
    )

    # Обработка LTO (Meson использует b_lto)
    if [[ "$USE_LTO" == "1" ]]; then
        myconf+=( -Db_lto=true )
    fi

    # Принудительно указываем путь к nasm, если Meson его "теряет"
    export NASM="/usr/bin/nasm"

    # Запуск meson setup
    meson setup "${myconf[@]}" ..

    # Сборка и установка
    ninja -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja install

    # Проверяем, что пути в dav1d.pc корректны для кросс-сборки
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/dav1d.pc"
    if [[ -f "$PC_FILE" ]]; then
        # Исправляем возможные абсолютные пути хоста на пути префикса
        sed -i "s|^prefix=.*|prefix=$FFBUILD_PREFIX|" "$PC_FILE"
        # Для статической линковки иногда нужны дополнительные флаги
        echo "Libs.private: -lm" >> "$PC_FILE"
    fi
}

ffbuild_configure() {
    echo --enable-libdav1d
}

ffbuild_unconfigure() {
    (( $(ffbuild_ffver) >= 404 )) || return 0
    echo --disable-libdav1d
}
