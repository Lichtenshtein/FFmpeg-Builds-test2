#!/bin/bash

SCRIPT_REPO="https://github.com/GNOME/librsvg.git"
SCRIPT_COMMIT="28b37154cddfda8a0782ee684f34a18964384b41"

ffbuild_enabled() {
    # 20-pixman.sh (нужен для Cairo).
    # 25-cairo.sh (нужен для Pango/Rsvg).
    # 40-pango.sh (нужен для Rsvg).
    return 0
}

ffbuild_dockerbuild() {
    # Librsvg требует Rust. Мы настроили его в Base Image.
    # Включаем кросс-линковку для Rust через переменные
    export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER="${FFBUILD_TOOLCHAIN}-gcc"
    export PKG_CONFIG_ALLOW_CROSS=1

    # В новых версиях librsvg лучше использовать Meson, если он есть, 
    # но официальный релиз 2.60 еще опирается на Autotools/Make
    ./autogen.sh

        # --disable-tools
    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --enable-static
        --disable-shared
        --disable-introspection
        --disable-pixbuf-loader
        --with-rust-target="$FFBUILD_RUST_TARGET"
    )

    ./configure "${myconf[@]}"

    # Сборка может быть тяжелой для RAM, ограничим потоки если нужно
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-librsvg
}

ffbuild_unconfigure() {
    echo --disable-librsvg
}
