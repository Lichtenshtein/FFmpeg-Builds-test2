#!/bin/bash

SCRIPT_REPO="https://github.com/ggml-org/whisper.cpp.git"
SCRIPT_COMMIT="aa1bc0d1a6dfd70dbb9f60c11df12441e03a9075"

ffbuild_depends() {
    echo base
    echo vulkan-headers
    echo vulkan-loader
    echo glslang-test
    echo shaderc
    echo spirv-cross
    echo opencl
    echo openvino
    echo curl
    echo sdl
}

ffbuild_enabled() {
    [[ $TARGET != *32 ]] || return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir build && cd build

    local myconf=(
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DBUILD_SHARED_LIBS_DEFAULT=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DWHISPER_BUILD_TESTS=OFF
        -DWHISPER_ALL_WARNINGS=OFF
        -DWHISPER_CURL=ON # to download models
        -DWHISPER_BUILD_EXAMPLES=OFF
        -DWHISPER_BUILD_SERVER=OFF
        -DWHISPER_USE_SYSTEM_GGML=OFF
        -DWHISPER_OPENVINO=ON
        -DWHISPER_SDL=ON # support for libSDL2
        -DGGML_ALL_WARNINGS=OFF
        -DGGML_AVX2=ON
        -DGGML_AVX512=$([ "${USE_AVX512}" == "1" ] && echo ON || echo OFF)
        -DGGML_AVX512_BF16=$([ "${USE_AVX512}" == "1" ] && echo ON || echo OFF)
        -DGGML_AVX512_VBMI=$([ "${USE_AVX512}" == "1" ] && echo ON || echo OFF)
        -DGGML_AVX512_VNNI=$([ "${USE_AVX512}" == "1" ] && echo ON || echo OFF)
        -DGGML_AVX=ON
        -DGGML_BACKEND_DL=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF) # build backends as dynamic libraries
        -DGGML_BMI2=ON
        -DGGML_BUILD_EXAMPLES=OFF
        -DGGML_BUILD_TESTS=OFF
        -DGGML_CCACHE=ON
        -DGGML_CUDA=OFF
        -DGGML_F16C=ON
        -DGGML_FMA=ON
        -DGGML_LTO=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DGGML_NATIVE=OFF
        -DGGML_OPENCL=ON
        -DGGML_OPENMP=$([ "${USE_OPENMP}" == "1" ] && echo ON || echo OFF)
        -DGGML_OPENVINO=ON
        -DGGML_SSE42=ON
        -DGGML_STATIC=$([ "${PREFER_SHARED}" == "1" ] && echo OFF || echo ON)
        -DGGML_VULKAN=ON
        -DGGML_WEBGPU=OFF
        )

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # Исправление имен файлов библиотек (MinGW prefix fix)
    # CMake в Windows часто сохраняет их как ggml-base.a, а линковщик ищет -lggml-base (т.е. libggml-base.a)
    log_info "Fixing library prefixes for MinGW..."
    find "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib" -name "ggml*.a" -not -name "lib*" -execdir mv {} lib{} \;
    find "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib" -name "whisper.a" -not -name "lib*" -execdir mv {} lib{} \;

    # Исправление pkg-config для FFmpeg
    # FFmpeg должен знать обо всех внутренних компонентах GGML
    local PC_FILE="$PC_DIR/whisper.pc"

    # Полный список компонентов GGML, которые создаются при сборке
    local GGML_LIBS="-lggml -lggml-base -lggml-cpu -lggml-vulkan -lggml-opencl"

    # Переписываем Libs и добавляем зависимости
    sed -i "s|^Libs:.*|Libs: -L\${libdir} -lwhisper $GGML_LIBS|" "$PC_FILE"

    # Добавляем системные зависимости Windows
    if ! grep -q "Libs.private" "$PC_FILE"; then
        echo "Libs.private: -lstdc++ -lsetupapi -lshlwapi" >> "$PC_FILE"
    fi

    # Указываем Requires для pkg-config, чтобы подтянулись флаги Vulkan и OpenCL
    if ! grep -q "Requires:" "$PC_FILE"; then
        echo "Requires: vulkan OpenCL" >> "$PC_FILE"
    else
        sed -i "s|^Requires:.*|Requires: vulkan OpenCL|" "$PC_FILE"
    fi
}

ffbuild_configure() {
    echo --enable-whisper
}

ffbuild_unconfigure() {
    echo --disable-whisper
}
