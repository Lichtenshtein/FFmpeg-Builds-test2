#!/bin/bash

SCRIPT_REPO="https://github.com/haasn/libplacebo.git"
SCRIPT_COMMIT="54e527552fa74467bcc7692e6985d35540861d19"

ffbuild_depends() {
    echo base
    echo vulkan-headers
    echo vulkan-loader
    echo glslang-test
    echo shaderc
    echo spirv-cross
    echo shaderc
    echo lcms2
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-submodule-clone"
}

ffbuild_dockerbuild() {
    set -e

    # Remove static build workaround for libplacebo
    # sed -i 's/DPL_EXPORT/DPL_STATIC/' src/meson.build

    mkdir -p build && cd build

    local myconf=(
        --buildtype=release
        --cross-file=/cross.meson
        --default-library=s$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        --prefix="$FFBUILD_PREFIX"
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false )
        -Dbench=false
        -Dc_std=c11
        -Dcpp_std=c++17
        -Ddemos=false
        -Dfuzz=false
        -Dglslang=enabled # glslang SPIR-V compiler
        -Dlcms2=enabled # LittleCMS 2 support
        -Dlibdovi=disabled # libdovi support
        -Ddovi=disabled # Dolby Vision reshaping support
        -Dshaderc=enabled # libshaderc SPIR-V compiler
        -Dtests=false
        -Dopengl=enabled # OpenGL-based renderer
        -Dgl-proc-addr=enabled # Enable built-in OpenGL loader; uses dlopen, dlsym
        -Dvk-proc-addr=enabled # Link directly against vkGetInstanceProcAddr from libvulkan.so
        -Dvulkan-registry="$FFBUILD_PREFIX"/share/vulkan/registry/vk.xml
        -Dvulkan=enabled
        -Dxxhash=enabled # faster replacement for internal siphash
    )

    if [[ $TARGET == win* ]]; then
        myconf+=(
            -Dd3d11=enabled
        )
    fi

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --cross-file=/cross.meson
        )
    fi

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS" \
        -Dc_link_args="$LDFLAGS" \
        -Dcpp_link_args="$LDFLAGS" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # Принудительно добавляем зависимости в pkg-config для статической линковки
    # sed -i 's/Libs:/Libs: -lshaderc_combined -lspirv-cross-c -lspirv-cross-glsl -lspirv-cross-core /' "$PC_DIR/libplacebo.pc"
    echo "Libs.private: -lstdc++ -lm -lshlwapi" >> "$PC_DIR/libplacebo.pc"
}

ffbuild_configure() {
    echo --enable-libplacebo
}

ffbuild_unconfigure() {
    echo --disable-libplacebo
}
