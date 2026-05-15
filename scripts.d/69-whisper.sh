#!/bin/bash

SCRIPT_REPO="https://github.com/ggml-org/whisper.cpp.git"
SCRIPT_COMMIT="aa1bc0d1a6dfd70dbb9f60c11df12441e03a9075"

ffbuild_depends() {
    echo base
    echo vulkan-headers
    echo vulkan-loader
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

    # Fixing the broken TBB search in whisper, which is tied to the Intel SDK folder structure
    if [ -f "ggml/src/ggml-openvino/CMakeLists.txt" ]; then
        sed -i 's|include("${OpenVINO_DIR}/../3rdparty/tbb/lib/cmake/TBB/TBBConfig.cmake")|find_package(TBB REQUIRED)|' ggml/src/ggml-openvino/CMakeLists.txt
    fi

    cat <<EOF > main-toolchain.cmake
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_C_COMPILER @TRIPLE@-gcc)
set(CMAKE_CXX_COMPILER @TRIPLE@-g++)
set(CMAKE_RC_COMPILER @TRIPLE@-windres)
set(CMAKE_AR @TRIPLE@-gcc-ar)
set(CMAKE_C_FLAGS "@CFLAGS@ @CPPFLAGS@" CACHE STRING "" FORCE)
set(CMAKE_CXX_FLAGS "@CXXFLAGS@ @CPPFLAGS@" CACHE STRING "" FORCE)
set(CMAKE_EXE_LINKER_FLAGS "@LDFLAGS@" CACHE STRING "" FORCE)
set(CMAKE_SYSROOT /opt/ct-ng/@TRIPLE@/sysroot)
set(CMAKE_FIND_ROOT_PATH /opt/ffbuild /opt/ct-ng/@TRIPLE@/sysroot)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
set(ENV{PKG_CONFIG_SYSROOT_DIR} "/")
set(ENV{PKG_CONFIG_PATH} "")
set(ENV{PKG_CONFIG_LIBDIR} "/opt/ffbuild/lib/pkgconfig:/opt/ffbuild/share/pkgconfig:/opt/ffbuild/lib64/pkgconfig")
EOF

    # Внедряем переменные через sed
    sed -i "s|@TRIPLE@|${FFBUILD_TOOLCHAIN}|g" main-toolchain.cmake
    sed -i "s|@CFLAGS@|${CFLAGS} ${USELTO}${USELTO_C}|g" main-toolchain.cmake
    sed -i "s|@CPPFLAGS@|${CPPFLAGS}|g" main-toolchain.cmake
    sed -i "s|@TRIPLE@|${FFBUILD_TOOLCHAIN}|g" main-toolchain.cmake
    sed -i "s|@CXXFLAGS@|${CXXFLAGS} ${USELTO}${USELTO_C}|g" main-toolchain.cmake
    sed -i "s|@LDFLAGS@|${LDFLAGS} ${USELTO}|g" main-toolchain.cmake

    # Создаем хост-тулчейн для сборщика шейдеров
    cat <<EOF > host-fix-toolchain.cmake
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_C_COMPILER gcc)
set(CMAKE_CXX_COMPILER g++)
set(CMAKE_C_FLAGS "-O3" CACHE STRING "" FORCE)
set(CMAKE_CXX_FLAGS "-O3" CACHE STRING "" FORCE)
set(CMAKE_EXE_LINKER_FLAGS "" CACHE STRING "" FORCE)
set(CMAKE_SHARED_LINKER_FLAGS "" CACHE STRING "" FORCE)
set(CMAKE_MODULE_LINKER_FLAGS "" CACHE STRING "" FORCE)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
EOF

    mkdir build && cd build

    local myconf=(
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_TOOLCHAIN_FILE="$(pwd)/../main-toolchain.cmake"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DBUILD_SHARED_LIBS_DEFAULT=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DWHISPER_BUILD_TESTS=OFF
        -DWHISPER_ALL_WARNINGS=OFF
        -DWHISPER_BUILD_EXAMPLES=OFF
        -DWHISPER_BUILD_SERVER=OFF
        -DWHISPER_USE_SYSTEM_GGML=OFF
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
        -DGGML_SYCL=OFF
        -DGGML_CUDA=OFF
        -DGGML_F16C=ON
        -DGGML_FMA=ON
        # -DGGML_LTO=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DGGML_NATIVE=OFF
        -DGGML_OPENMP=$([ "${USE_OPENMP}" == "1" ] && echo ON || echo OFF)
        -DGGML_SSE42=ON
        -DGGML_STATIC=$([ "${PREFER_SHARED}" == "1" ] && echo OFF || echo ON)
        -DGGML_WEBGPU=OFF
        #
        -DGGML_OPENCL=OFF
        -DWHISPER_SDL2=OFF # support for libSDL2
        -DWHISPER_CURL=OFF # to download models
        # VULKAN
        # -DGGML_VULKAN=ON
        # -DGGML_VULKAN_SHADERS_GEN_TOOLCHAIN="$(pwd)/../host-fix-toolchain.cmake"
        # -DVulkan_GLSLC_EXECUTABLE="/opt/glslc_host"
        # -DVulkan_INCLUDE_DIR="$FFBUILD_PREFIX/include"
        # -DVulkan_LIBRARY="$FFBUILD_PREFIX/lib/libvulkan.a"
        # -DGGML_VULKAN_CHECK_RESULTS=OFF
        # OPENVINO
        -DGGML_OPENVINO=ON
        -DWHISPER_OPENVINO=ON
        -DOpenVINO_DIR="$FFBUILD_PREFIX/lib/cmake"
        -DGGML_OPENVINO_SKIP_TBB_FIND=ON 
        )

    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # Ручная очистка артефактов Vulkan/Shaderc после whisper
    log_info "Final cleanup of Vulkan/Shaderc build tools..."
    if [[ -f "$INSTALL_ROOT/bin/glslc.exe" ]]; then
        find "$INSTALL_ROOT/bin" -name "glslc.exe" -delete
        find "$INSTALL_ROOT/lib" -name 'libshaderc_shared.dll' -o -name 'libshaderc_shared.dll.a' -delete
    fi
    rm -f /opt/glslc_host

    # CMake в Windows часто сохраняет их как ggml-base.a, а линковщик ищет -lggml-base (т.е. libggml-base.a)
    log_info "Fixing library prefixes for MinGW..."
    # CMake часто создает 'ggml.a' вместо 'libggml.a'
    find "$INSTALL_ROOT/lib" -name "ggml*.a" -not -name "lib*" -exec bash -c 'mv "$1" "${1%/*}/lib${1##*/}"' -- {} \;
    find "$INSTALL_ROOT/lib" -name "whisper.a" -not -name "lib*" -exec bash -c 'mv "$1" "${1%/*}/lib${1##*/}"' -- {} \;

    local PC_FILE="$PC_DIR/whisper.pc"
    if [[ -f "$PC_FILE" ]]; then
        log_info "Updating $PC_FILE with backend libraries..."
        local GGML_INTERNAL="-lggml-cpu -lggml -lggml-base"
        local SYS_LIBS="-lstdc++ -lsetupapi -lws2_32 -lshlwapi -lbcrypt -pthread"
        # Полностью перезаписываем строку Libs.private для идеального порядка
        sed -i '/^Libs.private:/d' "$PC_FILE"
        echo "Libs.private: ${GGML_INTERNAL} ${SYSTEM_MINGW}" >> "$PC_FILE"
        if [[ "${myconf[@]}" =~ "-DGGML_OPENCL=ON" ]]; then
            sed -i '/^Libs.private:/ s/$/ -lggml-opencl -lOpenCL/' "$PC_FILE"
        fi
        if [[ "${myconf[@]}" =~ "-DGGML_VULKAN=ON" ]]; then
            sed -i '/^Libs.private:/ s/$/ -lggml-vulkan -lvulkan/' "$PC_FILE"
        fi
        if [[ "${myconf[@]}" =~ "-DGGML_OPENVINO=ON" ]]; then
            echo "Requires.private: openvino" >> "$PC_FILE"
        fi
        ln -sf "$PC_FILE" "$PC_DIR/libwhisper.pc"
    else
        log_error "Cannot find .pc file at: $PC_FILE"
    fi
}

ffbuild_configure() {
    echo --enable-whisper
}

ffbuild_unconfigure() {
    echo --disable-whisper
}
