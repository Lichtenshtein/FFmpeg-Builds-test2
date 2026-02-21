#!/bin/bash
SCRIPT_REPO="https://gitlab.freedesktop.org/cairo/cairo.git"
SCRIPT_COMMIT="2a4589266388622f8c779721c8a4e090966fae79"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
}

ffbuild_dockerbuild() {
    set -e
    mkdir build && cd build

    # Отключаем X11, так как мы собираем под Windows (GDI/Win32)
    meson setup .. \
        --prefix="$FFBUILD_PREFIX" \
        --cross-file=/cross.meson \
        --buildtype=release \
        --wrap-mode=nodownload \
        --default-library=static \
        -Dtests=disabled \
        -Dzlib=enabled \
        -Dpng=enabled \
        -Dfontconfig=enabled \
        -Dfreetype=enabled \
        -Dtee=enabled \
        -Dglib=enabled \
        -Dlzo=disabled \
        -Dxcb=disabled \
        -Dxlib=disabled

    ninja -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja install

    # для статической линковки Cairo в FFmpeg под Windows
    # Cairo часто забывает прописать системные зависимости в .pc файл
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/cairo.pc"
    if [[ -f "$PC_FILE" ]]; then
        # Добавляем необходимые системные библиотеки Windows
        sed -i "s/Libs.private:/Libs.private: -lgdi32 -lmsimg32 -luser32 /" "$PC_FILE"
    fi
}

ffbuild_configure() {
    return 0
}