#!/bin/bash

SCRIPT_REPO="https://github.com/harfbuzz/harfbuzz.git"
SCRIPT_COMMIT="81ce4813c1d2ba1cf2f06aa2d2892aae7156bcaf"

ffbuild_depends() {
    echo freetype
    echo libicu
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    mkdir build && cd build

    local CFLAGS="$CFLAGS -DHARFBUZZ_STATIC"
    local CXXFLAGS="$CXXFLAGS -DHARFBUZZ_STATIC"
    local DEP_LIBS="-lfreetype -lsicuin -lsicuuc -lsicudt $LIBS"

    local myconf=(
        --cross-file=/cross.meson
        --prefix="$FFBUILD_PREFIX"
        --libdir=lib
        --buildtype=release
        --default-library=static
        -Dfreetype=enabled
        -Dglib=disabled
        -Dgobject=disabled
        -Dcairo=disabled
        -Dchafa=disabled
        -Dtests=disabled
        -Dintrospection=disabled
        -Ddocs=disabled
        -Ddoc_tests=false
        -Dutilities=disabled
        -Ddirectwrite=disabled
        -Dgdi=disabled
        -Dbenchmark=disabled
        -Dcpp_args="$CXXFLAGS"
        -Dc_args="$CFLAGS"
        -Dc_link_args="$LDFLAGS $DEP_LIBS"
        -Dcpp_link_args="$LDFLAGS $DEP_LIBS"
    )

    meson setup "${myconf[@]}" ..
    ninja -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja install

    get_deps_list
}

ffbuild_cppflags() {
    echo "-DHARFBUZZ_STATIC"
}