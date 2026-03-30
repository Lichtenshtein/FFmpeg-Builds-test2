#!/bin/bash

SCRIPT_REPO="https://github.com/KhronosGroup/Vulkan-Headers.git"
SCRIPT_COMMIT="49f1a381e2aec33ef32adf4a377b5a39ec016ec4"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    # копируем заголовки в префикс, чтобы лоадер и другие (libplacebo) их видели
    mkdir -p "$FFBUILD_DESTPREFIX"/include
    cp -r include/* "$FFBUILD_DESTPREFIX"/include/
    mkdir -p "$FFBUILD_DESTPREFIX"/share/vulkan/registry
    cp registry/vk.xml "$FFBUILD_DESTPREFIX"/share/vulkan/registry/

    mkdir build && cd build

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DVULKAN_HEADERS_ENABLE_MODULE=NO \
        -DVULKAN_HEADERS_ENABLE_TESTS=NO \
        -DVULKAN_HEADERS_ENABLE_INSTALL=YES .. || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

}
