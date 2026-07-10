#!/bin/bash

SCRIPT_REPO="https://github.com/haasn/libplacebo.git"
SCRIPT_COMMIT="a7a18af88ff0a17c04840dcb3246047bb6b46df3"

ffbuild_depends() {
    echo base
    echo vulkan-headers
    echo vulkan-loader
    echo glslang
    echo shaderc
    echo spirv-cross # main
    echo shaderc
    echo lcms2
    echo libxxhash
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-submodule-clone"
    echo "rm -rf fast_float/tests"
}

ffbuild_dockerbuild() {
    set -e

    # Исправляем meson.build, добавляя dirs: vulkan_lib_dirs в поиск glslang и MachineIndependent
    # В оригинале они ищутся только в системных путях, игнорируя vulkan-sdk префикс
    sed -i "s/find_library('glslang', required: required/find_library('glslang', required: required, dirs: vulkan_lib_dirs/g" src/glsl/meson.build
    sed -i "s/find_library('MachineIndependent',/find_library('MachineIndependent', dirs: vulkan_lib_dirs,/g" src/glsl/meson.build
    sed -i "s/find_library('OSDependent',/find_library('OSDependent', dirs: vulkan_lib_dirs,/g" src/glsl/meson.build
    sed -i "s/find_library('GenericCodeGen',/find_library('GenericCodeGen', dirs: vulkan_lib_dirs,/g" src/glsl/meson.build
    sed -i "s/find_library('SPIRV-Tools',/find_library('SPIRV-Tools', dirs: vulkan_lib_dirs,/g" src/glsl/meson.build
    sed -i "s/find_library('SPIRV-Tools-opt',/find_library('SPIRV-Tools-opt', dirs: vulkan_lib_dirs,/g" src/glsl/meson.build

    # Вырезаем поиск OGLCompiler, так как в новых glslang его больше нет
    # Мы заменяем его на пустую зависимость (disabler), чтобы не ломать логику массива glslang_deps
    sed -i "s/cxx.find_library('OGLCompiler',.*/disabler(),/g" src/glsl/meson.build

    mkdir -p build && cd build

    local myconf=(
        --buildtype=release
        --cross-file="$FFBUILD_MESON_CROSS"
        --default-library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        --prefix="$FFBUILD_PREFIX"
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false)
        -Dc_std=gnu17
        -Dcpp_std=gnu++20
        -Ddemos=false
        -Dfuzz=false
        -Dbench=false
        -Dtests=false
        -Ddebug-abort=false
        -Dglslang=enabled # glslang SPIR-V compiler
        -Dlcms=enabled # LittleCMS 2 support
        -Dlibdovi=disabled # libdovi support
        -Ddovi=disabled # Dolby Vision reshaping support
        -Dshaderc=enabled # libshaderc SPIR-V compiler
        -Dopengl=enabled # OpenGL-based renderer
        -Dgl-proc-addr=enabled # Enable built-in OpenGL loader; uses dlopen, dlsym
        #-Dvk-proc-addr=enabled # Link directly against vkGetInstanceProcAddr from libvulkan.so
        -Dvulkan-registry="$FFBUILD_PREFIX"/share/vulkan/registry/vk.xml
        -Dvulkan-sdk="$FFBUILD_PREFIX"
        -Dvulkan=enabled
        -Dxxhash=enabled # faster replacement for internal siphash
    )

    if [[ $TARGET == win* ]]; then
        myconf+=(
            -Dd3d11=enabled
        )
    fi

    local EXTRA_LDFLAGS="-lstdc++"
    local EXTRA_CFLAGS="-I${FFBUILD_PREFIX}/include/spirv_cross"

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $EXTRA_CFLAGS" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $EXTRA_CFLAGS" \
        -Dc_link_args="$LDFLAGS ${USELTO}${USELTO_L} $EXTRA_LDFLAGS" \
        -Dcpp_link_args="$LDFLAGS ${USELTO}${USELTO_L} $EXTRA_LDFLAGS" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local DEP_LIBS="-lshaderc_combined -lspirv-cross-c -lspirv-cross-glsl -lspirv-cross-core -lstdc++ -lm"
    local PC_FILE="$PC_DIR/libplacebo.pc"
    if [[ -f "$PC_FILE" ]]; then
        if grep -q "^Libs.private:" "$PC_FILE"; then
            sed -i "s|^Libs.private:.*|Libs.private: $DEP_LIBS|" "$PC_FILE"
        else
            sed -i "/^Libs:/ a Libs.private: $DEP_LIBS" "$PC_FILE"
        fi
        if [[ "${myconf[@]}" =~ "-Dd3d11=enabled" ]]; then
            sed -i 's|^Libs.private:.*|& -ld3d11 -ldxgi -luuid|' "$PC_FILE"
        fi
        # this confuses ffmpeg; it finds wrong d3d11.h
        # sed -i "s|^Cflags:.*|& -I\${includedir}/libplacebo|" "$PC_FILE"
    fi
}

ffbuild_configure() {
    echo --enable-libplacebo
}

ffbuild_unconfigure() {
    echo --disable-libplacebo
}
