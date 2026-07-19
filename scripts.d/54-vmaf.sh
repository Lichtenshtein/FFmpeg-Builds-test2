#!/bin/bash

SCRIPT_REPO="https://github.com/Netflix/vmaf.git"
SCRIPT_COMMIT="78e11b52c8fc1fcc6d15afd6c7479394fb3bc6af"

# SCRIPT_REPO2="https://github.com/VMAFx/vmafx.git"
# SCRIPT_COMMIT2="e8881bb4c6c7f22283ad01ea6e6a8d577c8ff09c"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "rm -rf \
libvmaf/test \
python/test \
resource/doc \
resource/images"
}

ffbuild_dockerbuild() {
    set -e

    log_info "Fixing Netflix Broken Windows ABI: Changing vmaf_init to pass configuration by pointer..."

    sed -i 's/int vmaf_init(VmafContext \*\*vmaf, VmafConfiguration cfg);/int vmaf_init(VmafContext \*\*vmaf, VmafConfiguration \*cfg);/g' "include/libvmaf/libvmaf.h"

    sed -i 's/int vmaf_init(VmafContext \*\*vmaf, VmafConfiguration cfg)/int vmaf_init(VmafContext \*\*vmaf, VmafConfiguration \*cfg)/g' "src/libvmaf.c"
    sed -i 's/v->cfg = cfg;/v->cfg = *cfg;/g' "src/libvmaf.c"
    sed -i 's/vmaf_set_cpu_flags_mask(~cfg.cpumask);/vmaf_set_cpu_flags_mask(~cfg->cpumask);/g' "src/libvmaf.c"
    sed -i 's/vmaf_set_log_level(cfg.log_level);/vmaf_set_log_level(cfg->log_level);/g' "src/libvmaf.c"

    # Temporary debug check: will log the patch result to be 100% sure
    log_info "Verifying header patch..."
    grep -n "vmaf_init" "include/libvmaf/libvmaf.h"

    if [[ "${USE_AVX512}" != "1" ]]; then
        # Create an avx-512 stub
        log_info "Creating AVX-512 stubs for libvmaf..."
        cat <<EOF > vmaf_avx512_stubs.c
void cambi_increment_range_avx512() {}
void cambi_decrement_range_avx512() {}
void get_derivative_data_for_row_avx512() {}
EOF
        # compile the object file using the same cross-compiler
        $CC $CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -c vmaf_avx512_stubs.c -o vmaf_avx512_stubs.o
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
    )

    if [[ $TARGET == linux* ]]; then
        myconf+=(
        -Denable_nvcc=false # Use clang to compile CUDA code
        -Denable_cuda=false # Enable CUDA support; requires nvcc
        )
    fi

    # added by patch
    # Check presence of the enable_discord_mode option in meson_options.txt
    if grep -q "enable_discord_mode" "../meson_options.txt" 2>/dev/null || grep -q "enable_discord_mode" "../libvmaf/meson_options.txt" 2>/dev/null; then
        log_info "Found enable_discord_mode option, enabling Discord mode..."
        myconf+=("-Denable_discord_mode=true")
    fi

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -DVMAF_PICTURE_POOL" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -DVMAF_PICTURE_POOL" \
        -Dc_link_args="$LDFLAGS ${USELTO}${USELTO_L}" \
        -Dcpp_link_args="$LDFLAGS ${USELTO}${USELTO_L}" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # adding a stub for avx512 to the library
    if [[ "${PREFER_SHARED}" != "1" ]]; then
        if [[ "${USE_AVX512}" != "1" ]]; then
        log_info "Injecting stubs into libvmaf.a"
        $AR rcs "$INSTALL_ROOT/lib/libvmaf.a" ../vmaf_avx512_stubs.o
        fi
    fi

    # log_info "Installing missing headers for FFmpeg compatibility..."
    # Copy only the MISSING files from the source files to the installation folder
    # Use the path from the root of the vmaf repository, where the source .h files are located
    # cp ${OP_VERB}n ../libvmaf/include/libvmaf/*.h "$INSTALL_ROOT/include/libvmaf/" || true

    # if dnn.h or vulkan.h is still missing
    # create them as empty placeholders so that FFmpeg configure doesn't crash.
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
