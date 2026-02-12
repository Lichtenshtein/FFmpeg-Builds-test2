#!/bin/bash

SCRIPT_REPO="https://github.com/GNOME/librsvg.git"
SCRIPT_COMMIT="v2.54.5"

ffbuild_enabled() {
    # librsvg требует Rust, убедимся что он есть
    [[ -n "$FFBUILD_RUST_TARGET" ]] || return -1
    return 0
}

ffbuild_dockerbuild() {
    # librsvg сейчас использует Autotools, который вызывает Cargo внутри
    ./autogen.sh
    
    # нужно подсказать Rust, какой таргет использовать
    export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER="${FFBUILD_TOOLCHAIN}-gcc"
    
    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --enable-static
        --disable-shared
        --disable-introspection
        --disable-pixbuf-loader
        --disable-tools
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
