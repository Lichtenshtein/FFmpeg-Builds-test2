#!/bin/bash

SCRIPT_REPO="https://github.com/Netflix/vmaf.git"
SCRIPT_COMMIT="332dde62838d91d8b5216e9822de58851f2fd64f"

# SCRIPT_REPO="https://github.com/lusoris/vmaf.git"
# SCRIPT_COMMIT="4336736ae2e52ab6a12728f9708777886fe6a5dd"

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
    sed -i 's/subdir(.tools.)//' meson.build

    mkdir -p build && cd build

    local myconf=(
        --cross-file="$FFBUILD_MESON_CROSS"
        --buildtype=release
        --default-library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        --prefix="$FFBUILD_PREFIX"
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false )
        -Dc_std=c11
        -Dcpp_std=c++17
        -Dbuilt_in_models=true
        -Denable_asm=true
        -Denable_avx512=$([ "${USE_AVX512}" == "1" ] && echo true || echo false )
        -Denable_docs=false
        -Denable_float=true
        -Denable_tests=false
        -Denable_tools=false
        -Denable_nvtx=false # Enable NVTX range support
        # added by patches
        # -Denable_discord_mode=true
        # -Denable_sycl=false # Enable Intel oneAPI SYCL/DPC++ support for GPU-accelerated feature extraction
        # -Denable_dnn=disabled # Build DNN runtime (ONNX Runtime) for tiny-model inference
        # -Denable_vulkan=disabled # Build Vulkan compute backend (ADR-0127 design; ADR-0175 scaffold; ADR-0178 / T5-1b runtime; ADR-0193 default-model kernel matrix complete). Default disabled; opt in to use it. Requires volk + Vulkan SDK 1.3+ + glslc + VMA.
        # -Dsycl_compiler=icpx # Path or name of the SYCL compiler (Intel icpx from oneAPI)
    )

    if [[ $TARGET == linux* ]]; then
        myconf+=(
        -Denable_nvcc=true # Use clang to compile CUDA code
        -Denable_cuda=true # Enable CUDA support; requires nvcc
        )
    fi

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS" \
        -Dc_link_args="$LDFLAGS" \
        -Dcpp_link_args="$LDFLAGS" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    sed -i 's/Libs.private:/Libs.private: -lstdc++/; t; $ a Libs.private: -lstdc++' "$PC_DIR/libvmaf.pc"
}

ffbuild_configure() {
    echo --enable-libvmaf
}

ffbuild_unconfigure() {
    echo --disable-libvmaf
}
