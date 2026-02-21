#!/bin/bash

SCRIPT_REPO="https://github.com/GNOME/librsvg.git"
SCRIPT_COMMIT="28b37154cddfda8a0782ee684f34a18964384b41"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
}

ffbuild_dockerbuild() {
    # Librsvg требует Rust. Мы настроили его в Base Image.
    # Включаем кросс-линковку для Rust через переменные
    export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER="${FFBUILD_TOOLCHAIN}-gcc"
    export PKG_CONFIG_ALLOW_CROSS=1
    export PKG_CONFIG_PATH="$FFBUILD_PREFIX/lib/pkgconfig:$FFBUILD_PREFIX/share/pkgconfig"

    # указываем Cargo, где искать либы, через RUSTFLAGS
    export RUSTFLAGS="-L native=$FFBUILD_PREFIX/lib -C linker=${FFBUILD_TOOLCHAIN}-gcc"

    # В новых версиях librsvg лучше использовать Meson, если он есть, 
    # но официальный релиз 2.60 еще опирается на Autotools/Make
    ./autogen.sh

    # --disable-pixbuf-loader экономит кучу места и убирает зависимость от gdk-pixbuf # --disable-tools
    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --enable-static
        --disable-shared
        --disable-introspection
        --disable-pixbuf-loader
        --disable-tools
        --with-rust-target="$FFBUILD_RUST_TARGET"
        CFLAGS="$CFLAGS -DGLIB_STATIC_COMPILATION"
    )

    ./configure "${myconf[@]}" || (cat config.log && exit 1)

    # Сборка может быть тяжелой для RAM, ограничим потоки если нужно
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Исправление .pc файла. 
    # librsvg-2.0.pc после сборки часто не содержит Cairo/Pango в Requires.private
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/librsvg-2.0.pc"
    if [[ -f "$PC_FILE" ]]; then
        # Добавляем необходимые системные либы для статической линковки
        sed -i 's/^Libs:.*/& -lxml2 -lpangocairo-1.0 -lpango-1.0 -lcairo -lgobject-2.0 -lglib-2.0 -lintl -liconv -lws2_32 -luserenv/' "$PC_FILE"
    fi
}

ffbuild_configure() {
    echo "--enable-librsvg"
}

ffbuild_unconfigure() {
    echo "--disable-librsvg"
}
