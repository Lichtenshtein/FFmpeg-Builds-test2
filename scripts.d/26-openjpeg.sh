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

    CFLAGS="$CFLAGS $CPPFLAGS -DOPJ_STATIC" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS -DOPJ_STATIC" \
    LDFLAGS="$LDFLAGS" \
    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF ) \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_STATIC_LIBS=ON \
        -DBUILD_LUTS_GENERATOR=OFF \
        -DBUILD_UNIT_TESTS=OFF \
        -DBUILD_CODEC=OFF \
        -DBUILD_DOC=OFF \
        -DWITH_ASTYLE=OFF \
        -DBUILD_TESTING=OFF .. || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

}

ffbuild_cppflags() {
    echo "-DOPJ_STATIC"
}

ffbuild_configure() {
    echo --enable-libopenjpeg
}

ffbuild_unconfigure() {
    echo --disable-libopenjpeg
}
