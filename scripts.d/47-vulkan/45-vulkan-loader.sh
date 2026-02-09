#!/bin/bash

SCRIPT_REPO="https://github.com/BtbN/Vulkan-Shim-Loader.git"
SCRIPT_COMMIT="9657ca8e395ef16c79b57c8bd3f4c1aebb319137"

SCRIPT_REPO2="https://github.com/KhronosGroup/Vulkan-Headers.git"
SCRIPT_COMMIT2="v1.4.337"
SCRIPT_TAGFILTER2="v?.*.*"

ffbuild_enabled() {
    (( $(ffbuild_ffver) > 404 )) || return -1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-mini-clone \"$SCRIPT_REPO2\" \"$SCRIPT_COMMIT2\" Vulkan-Headers"
}

ffbuild_dockerbuild() {

    if [[ -d "/builder/patches/vulkan_loader" ]]; then
        for patch in /builder/patches/vulkan_loader/*.patch; do
            echo "Applying $patch"
            patch -p1 < "$patch"
        done
    fi

    # Сначала копируем заголовки в префикс, чтобы лоадер и другие (libplacebo) их видели
    mkdir -p "$FFBUILD_DESTPREFIX"/include
    cp -r Vulkan-Headers/include/* "$FFBUILD_DESTPREFIX"/include/
    mkdir -p "$FFBUILD_DESTPREFIX"/share/vulkan/registry
    cp Vulkan-Headers/registry/vk.xml "$FFBUILD_DESTPREFIX"/share/vulkan/registry/

    mkdir build && cd build

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DVULKAN_SHIM_IMPERSONATE=ON ..
    make -j$(nproc)
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-vulkan
}

ffbuild_unconfigure() {
    (( $(ffbuild_ffver) >= 404 )) || return 0
    echo --disable-vulkan
}
