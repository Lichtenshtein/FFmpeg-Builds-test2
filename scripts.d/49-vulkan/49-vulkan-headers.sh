#!/bin/bash

SCRIPT_REPO="https://github.com/KhronosGroup/Vulkan-Headers.git"
SCRIPT_COMMIT="8d6039a455a7ecc7d2a592ff97f62db4e59b70bf"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    # копируем заголовки в префикс, чтобы лоадер и другие (libplacebo) их видели
    mkdir -p "$INSTALL_ROOT"/include
    cp -r include/* "$INSTALL_ROOT"/include/
    mkdir -p "$INSTALL_ROOT"/share/vulkan/registry
    cp registry/vk.xml "$INSTALL_ROOT"/share/vulkan/registry/

    mkdir -p build && cd build

    local myconf=(
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DVULKAN_HEADERS_ENABLE_MODULE=NO
        -DVULKAN_HEADERS_ENABLE_TESTS=NO
        -DVULKAN_HEADERS_ENABLE_INSTALL=YES
    )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1
}
