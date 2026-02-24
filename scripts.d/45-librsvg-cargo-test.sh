#!/bin/bash

SCRIPT_REPO="https://github.com/GNOME/librsvg.git"
SCRIPT_COMMIT="28b37154cddfda8a0782ee684f34a18964384b41"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    # Настройки для Cargo (Rust кросс-компиляция)
    export CARGO_HOME="/opt/cargo"
    export RUSTUP_HOME="/opt/rustup"
    # Ключевой момент: указываем Cargo использовать наш Mingw-линковщик
    # Имя переменной должно строго соответствовать таргету в верхнем регистре
    export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER="${FFBUILD_TOOLCHAIN}-gcc"
    export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_AR="${FFBUILD_TOOLCHAIN}-gcc-ar"
    export PKG_CONFIG_ALLOW_CROSS=1

    # Помогаем Rust найти либы C через переменные окружения
    export RUSTFLAGS="-L native=$FFBUILD_PREFIX/lib -C linker=${FFBUILD_TOOLCHAIN}-gcc"

    cargo cinstall --release \
        --target="x86_64-pc-windows-gnu" \
        --prefix="$FFBUILD_PREFIX" \
        --destdir="$FFBUILD_DESTDIR" \
        --library-type=staticlib \
        --features=avif \
        -p librsvg-c

    # Исправление .pc файла. 
    # librsvg-2.0.pc после сборки часто не содержит Cairo/Pango в Requires.private
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/librsvg-2.0.pc"
    if [[ -f "$PC_FILE" ]]; then
        # Librsvg (Rust) генерирует огромную статическую либу, которой нужны ВСЕ системные либы Windows
        sed -i 's/^Libs:.*/& -lxml2 -lpangocairo-1.0 -lpango-1.0 -lcairo -lgobject-2.0 -lglib-2.0 -lintl -liconv -lws2_32 -luserenv -lusp10 -lshlwapi -lsetupapi -lruntimeobject -lbcrypt -lntdll -lmsimg32 -lgdi32 -lstdc++/' "$PC_FILE"
    fi
}

ffbuild_configure() {
    echo "--enable-librsvg"
}

ffbuild_unconfigure() {
    echo "--disable-librsvg"
}
