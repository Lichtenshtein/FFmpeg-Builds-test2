#!/bin/bash

SCRIPT_REPO="https://github.com/uclouvain/openjpeg.git"
SCRIPT_COMMIT="d33cbecc148d3affcdf403211fddc2cc5d442379"

ffbuild_depends() {
    echo libtiff
    echo libpng
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

    local static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DOPJ_STATIC"

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_LUTS_GENERATOR=OFF
        -DBUILD_UNIT_TESTS=OFF
        -DBUILD_CODEC=OFF
        -DBUILD_DOC=OFF
        -DWITH_ASTYLE=OFF
        -DBUILD_TESTING=OFF
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( -DBUILD_STATIC_LIBS=OFF -DBUILD_SHARED_LIBS=ON ) || \
        myconf+=( -DBUILD_STATIC_LIBS=ON -DBUILD_SHARED_LIBS=OFF )

    CFLAGS="$CFLAGS $CPPFLAGS $static_flags" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS $static_flags" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1
}

ffbuild_cppflags() {
    echo "$static_flags"
}

ffbuild_configure() {
    echo --enable-libopenjpeg
}

ffbuild_unconfigure() {
    echo --disable-libopenjpeg
}
