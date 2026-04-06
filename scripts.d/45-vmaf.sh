#!/bin/bash

SCRIPT_REPO="https://github.com/Netflix/vmaf.git"
SCRIPT_COMMIT="332dde62838d91d8b5216e9822de58851f2fd64f"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    # Kill build of unused and broken tools
    # echo > libvmaf/tools/meson.build
    sed -i 's/subdir(.tools.)//' libvmaf/meson.build

    mkdir build && cd build

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --buildtype=release
        --default-library=static
        -Dcpp_std=c++17
        -Dc_std=c11
        -Dbuilt_in_models=true
        -Denable_tests=false
        -Denable_tools=false
        -Denable_asm=true
        -Denable_docs=false
        -Denable_avx512=$([ "${USE_AVX512}" == "1" ] && echo true || echo false )
        -Denable_float=true
        -Dbenchmarking=false
    )

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --cross-file=/cross.meson
        )
    else
        echo "Unknown target"
        return 1
    fi

    meson setup "${myconf[@]}" ../libvmaf \
        -Dc_args="$CFLAGS $CPPFLAGS" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS" \
        -Dc_link_args="$LDFLAGS" \
        -Dcpp_link_args="$LDFLAGS" || return 1

    ninja -j"$(nproc)" $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    sed -i 's/Libs.private:/Libs.private: -lstdc++/; t; $ a Libs.private: -lstdc++' "$PC_DIR/libvmaf.pc"

}

ffbuild_configure() {
    echo --enable-libvmaf
}

ffbuild_unconfigure() {
    echo --disable-libvmaf
}
