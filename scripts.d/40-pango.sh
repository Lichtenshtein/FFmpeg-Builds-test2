#!/bin/bash
SCRIPT_REPO="https://gitlab.gnome.org/GNOME/pango.git"
SCRIPT_COMMIT="147672f73a7fbfe6a4a89fd436c0b5f4eaa45a81"

ffbuild_dockerbuild() {
    mkdir build && cd build

    meson setup --prefix="$FFBUILD_PREFIX" \
        --cross-file=/cross.meson \
        --default-library=static \
        -Dintrospection=disabled \
        -Dfontconfig=enabled ..

    ninja -j$(nproc)  $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja install
}
