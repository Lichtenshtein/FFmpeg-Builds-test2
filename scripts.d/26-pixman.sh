#!/bin/bash
SCRIPT_REPO="https://gitlab.freedesktop.org/pixman/pixman.git"
SCRIPT_COMMIT="f824cac6478971c0f71e4dfe8a60ebf70224076a"

ffbuild_depends() {
    echo libpng
    echo glib2
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    mkdir build && cd build

    DEPS_LIB="-lpng16 -lglib-2.0 $LIB"

    meson setup --prefix="$FFBUILD_PREFIX" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS $DEPS_LIB" \
        --cross-file=/cross.meson \
        --default-library=static \
        -Dtests=disabled \
        -Ddemos=disabled ..

    ninja -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja install

    get_deps_list
}
