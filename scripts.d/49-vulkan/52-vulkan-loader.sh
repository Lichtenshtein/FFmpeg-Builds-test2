#!/bin/bash

SCRIPT_REPO="https://github.com/BtbN/Vulkan-Shim-Loader.git"
SCRIPT_COMMIT="65b3936528cd92eb4ea3de485d03f858a3850484"

SCRIPT_REPO2="https://github.com/KhronosGroup/Vulkan-Headers.git"
SCRIPT_COMMIT2="49f1a381e2aec33ef32adf4a377b5a39ec016ec4"

# original loader
# SCRIPT_REPO3="https://github.com/KhronosGroup/Vulkan-Loader.git"
# SCRIPT_COMMIT3="1a588f1982c14309873f2a86a60cfbfe5fb249f8"

# patches will not apply due to folder contains patches for original loader
export SKIP_PRE_PATCH=1

ffbuild_depends() {
    echo vulkan-headers
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
    SCRIPT_BRANCH="" # Сбрасываем, чтобы не мешала первой загрузке
    echo "git-mini-clone \"$SCRIPT_REPO2\" \"$SCRIPT_COMMIT2\" Vulkan-Headers"
}

ffbuild_dockerbuild() {
    set -e

    mkdir build && cd build

    local myconf=(
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DVULKAN_SHIM_IMPERSONATE=ON
    )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1
}

ffbuild_configure() {
    echo --enable-vulkan
}

ffbuild_unconfigure() {
    echo --disable-vulkan
}
