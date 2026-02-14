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
    mkdir build && cd build

    # Отключаем X11, так как мы собираем под Windows (GDI/Win32)
    meson setup --prefix="$FFBUILD_PREFIX" \
        --cross-file=/cross.meson \
        --default-library=static \
        -Dtests=disabled \
        -Dzlib=enabled \
        -Dpng=enabled \
        -Dfontconfig=enabled \
        -Dfreetype=enabled \
        -Dwin32=enabled \
        -Dx11=disabled \
        -Dglib=enabled ..

    ninja -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja install
    # Cairo иногда теряет gdi32 и msimg32
    echo "Libs.private: -lgdi32 -lmsimg32" >> "$FFBUILD_DESTPREFIX"/lib/pkgconfig/cairo.pc
}
