#!/bin/bash

SCRIPT_REPO="https://github.com/ggml-org/whisper.cpp.git"
SCRIPT_COMMIT="99613cb720b65036237d44b52f753b51f75c2797"

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

    if [[ "${BUILD_VINO}" == "1" ]]; then
        log_info "Applying OpenVINO pkg-config patch for Whisper..."
        # Создаем файл-заплатку, который вытягивает флаги через pkg-config
        cat << 'EOF' > patch-openvino.cmake
find_package(PkgConfig REQUIRED)
pkg_check_modules(OV REQUIRED openvino)
pkg_check_modules(TBB REQUIRED tbb)

# Create a fake CMake target openvino::runtime
add_library(openvino::runtime INTERFACE IMPORTED)
target_link_libraries(openvino::runtime INTERFACE ${OV_LIBRARIES} ${TBB_LIBRARIES})
target_include_directories(openvino::runtime INTERFACE ${OV_INCLUDE_DIRS} ${TBB_INCLUDE_DIRS})

# Create a fake CMake target TBB::tbb
add_library(TBB::tbb INTERFACE IMPORTED)
target_link_libraries(TBB::tbb INTERFACE ${TBB_LIBRARIES})
target_include_directories(TBB::tbb INTERFACE ${TBB_INCLUDE_DIRS})

# Globally override find_package for OpenVINO so it doesn't search for anything
macro(find_package name)
    if("${name}" STREQUAL "OpenVINO")
        set(OpenVINO_FOUND ON)
        set(OpenVINO_DIR "STUB")
    else()
        _find_package(${ARGV})
    endif()
endmacro()
EOF

        # Внедряем заплатку в САМЫЙ КОРЕНЬ проекта (главный CMakeLists.txt) на первую строку
        sed -i '1i include("${CMAKE_CURRENT_SOURCE_DIR}/patch-openvino.cmake")' CMakeLists.txt

        # Вырезаем хардкод TBBConfig из всех подпапок ggml
        find ggml/ -name "CMakeLists.txt" -exec sed -i 's|include(.*TBBConfig.cmake")|# cut|g' {} +
    else
        log_info "OpenVINO is disabled. Skipping patch."
    fi

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-D__TBB_DYNAMIC_LOAD_ENABLED=0 -DOPENVINO_STATIC_LIBRARY"

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

    sed -i "s|@TRIPLE@|${FFBUILD_TOOLCHAIN}|g" main-toolchain.cmake
    sed -i "s|@CFLAGS@|${CFLAGS} ${USELTO}${USELTO_C} $static_flags|g" main-toolchain.cmake
    sed -i "s|@CPPFLAGS@|${CPPFLAGS}|g" main-toolchain.cmake
    sed -i "s|@TRIPLE@|${FFBUILD_TOOLCHAIN}|g" main-toolchain.cmake
    sed -i "s|@CXXFLAGS@|${CXXFLAGS} ${USELTO}${USELTO_C} $static_flags|g" main-toolchain.cmake
    sed -i "s|@LDFLAGS@|${LDFLAGS} ${USELTO}|g" main-toolchain.cmake

    # Создаем хост-тулчейн для сборщика шейдеров
    cat <<EOF > host-fix-toolchain.cmake
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_C_COMPILER gcc)
set(CMAKE_CXX_COMPILER g++)
set(CMAKE_C_FLAGS "-O3 -pipe" CACHE STRING "" FORCE)
set(CMAKE_CXX_FLAGS "-O3 -pipe" CACHE STRING "" FORCE)
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
        -DGGML_OPENCL=ON
        -DWHISPER_SDL2=ON # support for libSDL2
        -DWHISPER_CURL=ON # to download models
        # VULKAN
        -DGGML_VULKAN=ON
        -DGGML_VULKAN_SHADERS_GEN_TOOLCHAIN="$(pwd)/../host-fix-toolchain.cmake"
        -DVulkan_GLSLC_EXECUTABLE="/opt/glslc"
        -DVulkan_INCLUDE_DIR="$FFBUILD_PREFIX/include"
        -DVulkan_LIBRARY="$FFBUILD_PREFIX/lib/libvulkan.a"
        -DGGML_VULKAN_CHECK_RESULTS=OFF
        # OPENVINO
        -DGGML_OPENVINO=$([ "${BUILD_VINO}" == "1" ] && echo ON || echo OFF)
        -DWHISPER_OPENVINO=$([ "${BUILD_VINO}" == "1" ] && echo ON || echo OFF)
        # -DOpenVINO_DIR="$FFBUILD_PREFIX/lib/cmake"
        -DGGML_OPENVINO_SKIP_TBB_FIND=ON # don't delete
        )

    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # Ручная очистка артефактов Vulkan/Shaderc после whisper
    if [[ -f "$INSTALL_ROOT/bin/glslc.exe" ]]; then
        log_info "Final cleanup of Vulkan/Shaderc build tools..."
        find "$INSTALL_ROOT/bin" -name "glslc.exe" -delete
        if [[ "${PREFER_SHARED}" != "1" ]]; then
            find "$INSTALL_ROOT/lib" -name 'libshaderc_shared.dll' -o -name 'libshaderc_shared.dll.a' -delete
            rm -f /opt/glslc
        fi
    fi

    # CMake в Windows часто сохраняет их как ggml-base.a, а линковщик ищет -lggml-base (т.е. libggml-base.a)
    if [[ "${PREFER_SHARED}" == "1" ]]; then
        # Фикс префиксов импортных библиотек, если CMake назвал их некорректно
        log_info "Fixing shared library prefixes for MinGW..."
        find "$INSTALL_ROOT/lib" -name "ggml*.dll.a" -not -name "lib*" -exec bash -c 'mv "$1" "${1%/*}/lib${1##*/}"' -- {} \;
        find "$INSTALL_ROOT/lib" -name "whisper*.dll.a" -not -name "lib*" -exec bash -c 'mv "$1" "${1%/*}/lib${1##*/}"' -- {} \;
    else
        log_info "Fixing library prefixes for MinGW..."
        # CMake часто создает 'ggml.a' вместо 'libggml.a'
        find "$INSTALL_ROOT/lib" -name "ggml*.a" -not -name "lib*" -exec bash -c 'mv "$1" "${1%/*}/lib${1##*/}"' -- {} \;
        find "$INSTALL_ROOT/lib" -name "whisper.a" -not -name "lib*" -exec bash -c 'mv "$1" "${1%/*}/lib${1##*/}"' -- {} \;
    fi

    local PC_FILE="$PC_DIR/whisper.pc"
    if [[ -f "$PC_FILE" ]]; then
        log_info "Updating $PC_FILE with backend libraries..."
        local GGML_INTERNAL="-lggml-cpu -lggml -lggml-base"
        local SYS_LIBS="-lstdc++ -lsetupapi -lws2_32 -lshlwapi -lbcrypt -pthread"
        # Полностью перезаписываем строку Libs.private для идеального порядка
        sed -i '/^Libs.private:/d' "$PC_FILE"
        echo "Libs.private: ${GGML_INTERNAL} ${SYS_LIBS}" >> "$PC_FILE"
        if [[ "${myconf[@]}" =~ "-DGGML_OPENCL=ON" ]]; then
            sed -i '/^Libs.private:/ s/$/ -lggml-opencl -lOpenCL/' "$PC_FILE"
        fi
        if [[ "${myconf[@]}" =~ "-DGGML_VULKAN=ON" ]]; then
            sed -i '/^Libs.private:/ s/$/ -lggml-vulkan -lshaderc_combined/' "$PC_FILE"
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
