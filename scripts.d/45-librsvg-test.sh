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

    meson setup build \
        --prefix="$FFBUILD_PREFIX" \
        --cross-file="$FFBUILD_CMAKE_TOOLCHAIN" \
        --buildtype=release \
        --default-library=static \
        --wrap-mode=nodownload \
        -Dintrospection=disabled \
        -Dpixbuf=disabled \
        -Dpixbuf-loader=disabled \
        -Dvala=disabled \
        -Ddocs=disabled \
        -Dtests=false \
        -Drsvg-convert=disabled \
        -Davif=enabled \
        -Dtriplet="$FFBUILD_RUST_TARGET" \
        || (tail -n 100 build/meson-logs/meson-log.txt && exit 1)

    ninja -C build -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja -C build install

    # Исправление .pc файла. 
    # librsvg-2.0.pc после сборки часто не содержит Cairo/Pango в Requires.private
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/librsvg-2.0.pc"
    if [[ -f "$PC_FILE" ]]; then
        # Добавлены -lusp10 и -lshlwapi (нужны для Pango) и -lxml2
        sed -i 's/^Libs:.*/& -lxml2 -lpangocairo-1.0 -lpango-1.0 -lcairo -lgobject-2.0 -lglib-2.0 -lintl -liconv -lws2_32 -luserenv -lusp10 -lshlwapi -lsetupapi -lruntimeobject/' "$PC_FILE"
    fi
}

ffbuild_configure() {
    echo "--enable-librsvg"
}

ffbuild_unconfigure() {
    echo "--disable-librsvg"
}
