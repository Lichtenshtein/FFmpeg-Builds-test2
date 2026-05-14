#!/bin/bash

SCRIPT_REPO="https://github.com/Netflix/vmaf.git"
SCRIPT_COMMIT="332dde62838d91d8b5216e9822de58851f2fd64f"

# SCRIPT_REPO="https://github.com/lusoris/vmaf.git"
# SCRIPT_COMMIT="49c738b0584337a45048429581214063e80831e2"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    if [[ "${USE_AVX512}" != "1" ]]; then
        # создаем заглушку avx-512
        log_info "Creating AVX-512 stubs for libvmaf..."
        cat <<EOF > vmaf_avx512_stubs.c
void cambi_increment_range_avx512() {}
void cambi_decrement_range_avx512() {}
void get_derivative_data_for_row_avx512() {}
EOF
        # Компилируем объектный файл тем же кросс-компилятором
        $CC $CFLAGS $CPPFLAGS -c vmaf_avx512_stubs.c -o vmaf_avx512_stubs.o
    fi

    # Kill build of unused and broken tools
    # echo > libvmaf/tools/meson.build
    sed -i 's/subdir(.tools.)//' meson.build

    mkdir -p build && cd build

    local myconf=(
        --cross-file="$FFBUILD_MESON_CROSS"
        --buildtype=release
        --default-library=$([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        --prefix="$FFBUILD_PREFIX"
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false)
        -Dc_std=gnu17
        -Dcpp_std=gnu++20
        -Dbuilt_in_models=true
        -Denable_asm=true
        -Denable_avx512=$([ "${USE_AVX512}" == "1" ] && echo true || echo false)
        -Denable_docs=false
        -Denable_float=true
        -Denable_tests=false
        # -Denable_tools=false
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
        -Dc_args="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
        -Dc_link_args="$LDFLAGS ${USELTO}" \
        -Dcpp_link_args="$LDFLAGS ${USELTO}" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # вшиваем заглушку для avx512 в библиотеку
    if [[ "${PREFER_SHARED}" != "1" ]]; then
        if [[ "${USE_AVX512}" != "1" ]]; then
        log_info "Injecting stubs into libvmaf.a"
        $AR rcs "$INSTALL_ROOT/lib/libvmaf.a" ../vmaf_avx512_stubs.o
        fi
    fi

    # log_info "Installing missing headers for FFmpeg compatibility..."
    # Копируем из исходников в папку установки только ОТСУТСТВУЮЩИЕ файлы
    # используем путь от корня репозитория vmaf, где лежат исходные .h
    # cp -vn ../libvmaf/include/libvmaf/*.h "$INSTALL_ROOT/include/libvmaf/" || true

    # если dnn.h или vulkan.h всё еще нет
    # создаем их как пустые заглушки, чтобы configure FFmpeg не падал
    # for header in dnn.h libvmaf_vulkan.h libvmaf_cuda.h libvmaf_sycl.h; do
        # if [ ! -f "$INSTALL_ROOT/include/libvmaf/$header" ]; then
            # touch "$INSTALL_ROOT/include/libvmaf/$header"
        # fi
    # done

    mkdir -p "$PC_DIR"
    sed -i 's/Libs.private:/Libs.private: -lstdc++/; t; $ a Libs.private: -lstdc++' "$PC_DIR/libvmaf.pc"
    sed -i 's| -pthread||g' "$PC_DIR/libvmaf.pc"

    ln -sf libvmaf.pc "$PC_DIR/vmaf.pc"
}

ffbuild_configure() {
    echo --enable-libvmaf
}

ffbuild_unconfigure() {
    echo --disable-libvmaf
}
