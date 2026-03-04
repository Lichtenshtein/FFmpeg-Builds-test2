#!/bin/bash

SCRIPT_REPO="https://github.com/fribidi/fribidi.git"
SCRIPT_COMMIT="b28f43bd3e8e31a5967830f721bab218c1aa114c"
# SCRIPT_REPO="https://github.com/Treata11/fribidi.git"
# SCRIPT_COMMIT="1a1ac31d25eeee9efd3d496b04b3b29ae81b8809"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    apply_patches

    mkdir build && cd build

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --cross-file=/cross.meson
        --buildtype=release
        --default-library=static
        -Dbin=false
        -Ddocs=false
        -Dtests=false
    )

    meson setup "${myconf[@]}" ..
    ninja -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja install

    sed -i 's/Cflags:/Cflags: -DFRIBIDI_LIB_STATIC/' "$FFBUILD_DESTPREFIX"/lib/pkgconfig/fribidi.pc

    get_deps_list
}

ffbuild_configure() {
    echo --enable-libfribidi
}

ffbuild_unconfigure() {
    echo --disable-libfribidi
}
