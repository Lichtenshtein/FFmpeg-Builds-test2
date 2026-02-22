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
    # mkdir build && cd build

    meson setup build \
        --prefix="$FFBUILD_PREFIX" \
        --cross-file=/cross.meson \
        --buildtype=release \
        --default-library=static \
        --wrap-mode=nodownload \
        -Dtests=disabled \
        -Dzlib=enabled \
        -Dpng=enabled \
        -Dfontconfig=enabled \
        -Dfreetype=enabled \
        -Dtee=enabled \
        -Dglib=enabled \
        -Dxcb=disabled \
        -Dxlib=disabled \
        -Dpixman=enabled \
        || (tail -n 100 build/meson-logs/meson-log.txt && exit 1)

    ninja -C build -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja -C build install

    # для статической линковки Cairo в FFmpeg под Windows
    # Cairo часто забывает прописать системные зависимости в .pc файл
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/cairo.pc"
    if [[ -f "$PC_FILE" ]]; then
        # Добавляем gdi32 и msimg32 (нужны для win32-surface)
        sed -i 's/^Libs:.*/& -lgdi32 -lmsimg32 -luser32/' "$PC_FILE"
    fi
}