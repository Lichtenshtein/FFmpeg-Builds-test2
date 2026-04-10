#!/bin/bash

# SCRIPT_REPO="https://github.com/xiph/ogg.git"
# SCRIPT_COMMIT="0288fadac3ac62d453409dfc83e9c4ab617d2472"

SCRIPT_REPO="https://github.com/sezero/ogg.git"
SCRIPT_COMMIT="b7069ef0ee3e2819cda3b60be79655d88cdb67ab"
SCRIPT_BRANCH="sezero"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build && cd build

    local myconf=(
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON # use pic
        -DBUILD_FRAMEWORK=OFF # Build Framework bundle for OSX
        -DINSTALL_DOCS=OFF
        -DINSTALL_PKG_CONFIG_MODULE=ON # Install ogg.pc file
        -DINSTALL_CMAKE_PACKAGE_MODULE=ON # CMake package configuration module
    )

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1
}
