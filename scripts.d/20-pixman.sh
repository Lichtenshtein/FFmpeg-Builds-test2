#!/bin/bash
SCRIPT_REPO="https://gitlab.freedesktop.org/pixman/pixman.git"
SCRIPT_COMMIT="f824cac6478971c0f71e4dfe8a60ebf70224076a"

ffbuild_dockerbuild() {
    mkdir build && cd build

    meson setup --prefix="$FFBUILD_PREFIX" \
        --cross-file=/cross.meson \
        --default-library=static \
        -Dtests=disabled \
        -Ddemos=disabled ..

    ninja -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja install
}
