#!/bin/bash

SCRIPT_REPO="https://github.com/GNOME/librsvg.git"
SCRIPT_COMMIT="28b37154cddfda8a0782ee684f34a18964384b41"

ffbuild_depends() {
    echo zlib
    echo xz
    echo bzlib
    echo libxml2
    echo glib2
    echo brotli
    echo cairo
    echo pango
    echo dav1d
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
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
        -p librsvg-c $CARGO_V || return 1

    # Исправление .pc файла. 
    # librsvg-2.0.pc после сборки часто не содержит Cairo/Pango в Requires.private
    local PC_FILE="$PC_DIR/librsvg-2.0.pc"
    if [[ -f "$PC_FILE" ]]; then
        # Librsvg (Rust) генерирует огромную статическую либу, которой нужны ВСЕ системные либы Windows
        sed -i 's/^Libs:.*/& -lpangocairo-1.0 -lpangowin32-1.0 -lpangoft2-1.0 -lpango-1.0 -lgio-2.0 -lgthread-2.0 -lglib-2.0 -ldav1d -lxml2 -lintl -liconv -lcharset -luserenv -lusp10 -lruntimeobject -lntdll -lmsimg32 -lgdi32 -lstdc++/' "$PC_FILE"
    fi

}

ffbuild_configure() {
    echo "--enable-librsvg"
}

ffbuild_unconfigure() {
    echo "--disable-librsvg"
}
