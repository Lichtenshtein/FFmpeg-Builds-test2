#!/bin/bash

SCRIPT_REPO="https://github.com/hoene/libmysofa.git"
SCRIPT_COMMIT="3b7427c295d063724601f175ca05f81e29e3cc1a"

ffbuild_depends() {
    echo zlib
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "rm -rf tests"
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DBUILD_STATIC_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo OFF || echo ON)
        -DBUILD_TESTS=OFF
    )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1
}

ffbuild_configure() {
    echo --enable-libmysofa
}

ffbuild_unconfigure() {
    echo --disable-libmysofa
}