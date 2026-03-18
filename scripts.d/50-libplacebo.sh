#!/bin/bash

SCRIPT_REPO="https://github.com/haasn/libplacebo.git"
SCRIPT_COMMIT="c93aa134ab62365ce1177efff99b8e1e66a818e7"

ffbuild_depends() {
    echo base
    echo vulkan-headers
    echo vulkan-loader
    echo glslang-test
    echo shaderc
    echo spirv-cross
    echo shaderc
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
    apply_patches

    sed -i 's/DPL_EXPORT/DPL_STATIC/' src/meson.build

    mkdir build && cd build

    export CFLAGS="$(echo $CFLAGS | sed 's/-std=c11//g')"
    export CXXFLAGS="$(echo $CXXFLAGS | sed 's/-std=c++17//g')"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --buildtype=release
        --default-library=static
        --cross-file=/cross.meson
        -Dcpp_std=c++17
        -Dc_std=c11
        -Dvulkan=enabled
        -Dshaderc=enabled
        -Dglslang=enabled
        -Dlcms2=enabled
        -Dvk-proc-addr=enabled
        -Dvulkan-registry="$FFBUILD_PREFIX"/share/vulkan/registry/vk.xml
        -Ddemos=false
        -Dtests=false
        -Dbench=false
        -Dfuzz=false
        -Dlibdovi=disabled
        -Dxxhash=disabled
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
    else
        echo "Unknown target"
        return 1
    fi

    meson "${myconf[@]}" .. || return 1
    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # Принудительно добавляем зависимости в pkg-config для статической линковки
    sed -i 's/Libs:/Libs: -lshaderc_combined -lspirv-cross-c -lspirv-cross-glsl -lspirv-cross-core /' "$FFBUILD_DESTPREFIX"/lib/pkgconfig/libplacebo.pc
    echo "Libs.private: -lstdc++ -lm -lshlwapi" >> "$FFBUILD_DESTPREFIX"/lib/pkgconfig/libplacebo.pc

    get_deps_list
}

ffbuild_configure() {
    echo --enable-libplacebo
}

ffbuild_unconfigure() {
    echo --disable-libplacebo
}
