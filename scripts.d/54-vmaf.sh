#!/bin/bash

SCRIPT_REPO="https://github.com/Netflix/vmaf.git"
SCRIPT_COMMIT="30f472b146b9228f76c684360d6a976774290b5e"

# SCRIPT_REPO="https://github.com/lusoris/vmaf.git"
# SCRIPT_COMMIT="49c738b0584337a45048429581214063e80831e2"

export SKIP_PRE_PATCH=1

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    # Фильтруем CFLAGS для Meson, оставляя только критически важную оптимизацию и выравнивание стека.
    # Meson сам добавит нужные стандарты (-std=gnu17), уровни предупреждений и отладку.
    local EXTRA_CFLAGS="-O3 -march=${CPU_ARCH} -mtune=${CPU_TUNE} -mavx2 -mfma -mstackrealign -mms-bitfields -fstack-protector-strong"
    local EXTRA_CXXFLAGS="-O3 -march=${CPU_ARCH} -mtune=${CPU_TUNE} -mavx2 -mfma -mstackrealign -mms-bitfields -fstack-protector-strong"

    if [[ "${USE_AVX512}" != "1" ]]; then
        log_info "Creating AVX-512 stubs for libvmaf..."
        cat <<EOF > vmaf_avx512_stubs.c
void cambi_increment_range_avx512() {}
void cambi_decrement_range_avx512() {}
void get_derivative_data_for_row_avx512() {}
EOF
        # Компилируем заглушку с жестким выравниванием стека
        $CC $EXTRA_CFLAGS -c vmaf_avx512_stubs.c -o vmaf_avx512_stubs.o
    fi

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
        -Denable_nvtx=false
    )

    if [[ $TARGET == linux* ]]; then
        myconf+=(
            -Denable_nvcc=false
            -Denable_cuda=false
        )
    fi

    if grep -q "enable_discord_mode" "../meson_options.txt" 2>/dev/null || grep -q "enable_discord_mode" "../libvmaf/meson_options.txt" 2>/dev/null; then
        myconf+=("-Denable_discord_mode=true")
    fi

    # Передаем очищенные и строгие аргументы компилятора
    meson setup "${myconf[@]}" .. \
        -Dc_args="$EXTRA_CFLAGS" \
        -Dcpp_args="$EXTRA_CXXFLAGS" \
        -Dc_link_args="$LDFLAGS" \
        -Dcpp_link_args="$LDFLAGS" || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    if [[ "${PREFER_SHARED}" != "1" ]]; then
        if [[ "${USE_AVX512}" != "1" ]]; then
            log_info "Injecting stubs into libvmaf.a"
            # Используем явный путь к установленной статике в дестдире
            $AR rcs "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/libvmaf.a" ../vmaf_avx512_stubs.o
        fi
    fi

    mkdir -p "$PC_DIR"
    # Исправляем генерацию pkg-config
    sed -i 's/Libs.private:/Libs.private: -lstdc++ -lwinpthread/; t; $ a Libs.private: -lstdc++ -lwinpthread' "$PC_DIR/libvmaf.pc"
    sed -i 's| -pthread||g' "$PC_DIR/libvmaf.pc"

    ln -sf libvmaf.pc "$PC_DIR/vmaf.pc"
}

ffbuild_configure() {
    echo --enable-libvmaf
}

ffbuild_unconfigure() {
    echo --disable-libvmaf
}
