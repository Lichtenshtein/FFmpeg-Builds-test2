#!/bin/bash

SCRIPT_REPO="https://github.com/v-novaltd/LCEVCdec.git"
SCRIPT_COMMIT="b033a6d1f68a80ac1d972f34cf1740000b544571"

ffbuild_depends() {
    echo vulkan-headers
    echo shaderc
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    export SKIP_POST_STRIP=1

    mkdir -p build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DVN_SDK_BENCHMARK=OFF
        -DVN_SDK_DIAGNOSTICS_ASYNC=OFF
        -DVN_SDK_DOCS=OFF
        -DVN_SDK_EXECUTABLES=OFF
        # -DVN_SDK_FORCE_OVERLAY=OFF # old
        -DVN_SDK_GENERATE_PGO=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF) # this is NOT LTO
        -DVN_SDK_JSON_CONFIG=OFF
        # -DVN_SDK_LTO=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DVN_SDK_METRICS=OFF
        -DVN_SDK_PIPELINE_CPU=ON
        # -DVN_SDK_PIPELINE_LEGACY=ON # ON; old
        -DVN_SDK_PIPELINE_VULKAN=ON # OFF; experimental Vulkan GPU pipeline for decoding LCEVC stream
        -DVN_SDK_SAMPLE_SOURCE=OFF
        -DVN_SDK_SIMD=ON
        -DVN_SDK_SYSTEM_INSTALL=ON
        -DVN_SDK_THREADING=ON
        -DVN_SDK_TRACING=OFF
        -DVN_SDK_UNIT_TESTS=OFF
        -DVN_STRIP_RELEASE=ON
        )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( -DBUILD_SHARED_LIBS=ON VN_MSVC_RUNTIME_STATIC=OFF ) || \
        myconf+=( -DBUILD_SHARED_LIBS=OFF VN_MSVC_RUNTIME_STATIC=ON )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # if [[ "${myconf[@]}" =~ "-DVN_SDK_PIPELINE_LEGACY=ON" ]]; then
        # local SDK_PIPELINE_LEGACY="-llcevc_dec_legacy"
    # fi

    # local PC_FILE="$PC_DIR/lcevc_dec.pc"
    # cat <<EOF > "$PC_FILE"
# prefix=$FFBUILD_PREFIX
# exec_prefix=\${prefix}
# libdir=\${prefix}/lib
# includedir=\${prefix}/include

# Name: lcevc_dec
# Description: LCEVC Decoder SDK (Static Combined)
# Version: 4.1.0
# Libs: -L\${libdir} -llcevc_dec_api -llcevc_dec_api_utility -llcevc_dec_common -llcevc_dec_enhancement -llcevc_dec_extract $SDK_PIPELINE_LEGACY -llcevc_dec_overlay_images -llcevc_dec_pipeline -llcevc_dec_pipeline_cpu -llcevc_dec_pipeline_legacy -llcevc_dec_pipeline_vulkan -llcevc_dec_pixel_processing -llcevc_dec_sequencer
# Libs.private: -lstdc++ -lm
# Cflags: -I\${includedir} -I\${includedir}/LCEVC -DVNEnablePublicAPIExport
# EOF

    local PC_FILE="$PC_DIR/lcevc_dec.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i 's|^Libs.private:.*|& -llcevc_dec_extract.a|' "$PC_FILE"
        sed -i "s|^Cflags:.*|& -I\${includedir}/LCEVC|" "$PC_FILE"

        # Вырезаем glfw3 из строки Requires.private
        sed -i 's/glfw3//g' "$PC_FILE"
    
        # Подчищаем возможные висячие пробелы, чтобы строка осталась валидной
        sed -i 's/Requires.private:  /Requires.private: /g' "$PC_FILE"
        sed -i 's/Requires.private: *$/Requires.private: vulkan/g' "$PC_FILE"
    fi

    # Удаляем лишние/кривые .pc файлы, чтобы pkg-config не путался
    rm -f "$PC_DIR"/lcevc_dec_utility.pc "$PC_DIR"/lcevc_dec_extract.pc

    rm -rf "$FFBUILD_DESTPREFIX"/share
}

ffbuild_configure() {
    echo --enable-liblcevc_dec
}

ffbuild_unconfigure() {
    echo --disable-liblcevc_dec
}
