#!/bin/bash

SCRIPT_REPO="https://github.com/ggml-org/whisper.cpp.git"
SCRIPT_COMMIT="6fc7c33b4c3a2cec83e4b65abd5e96a890480375"

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
    echo openblas
}

ffbuild_enabled() {
    [[ $TARGET != *32 ]] || return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "rm -rf examples"
}

ffbuild_dockerbuild() {
    set -e

    # Disable functions that cause threading issues on Windows
    if [[ $TARGET == win64 ]]; then
        sed -i '/THREAD_POWER_THROTTLING_STATE/,/}/ { /#endif/!s/^/\/\// }' ggml/src/ggml-cpu/ggml-cpu.c
    fi

    # Increase n_threads from 4 to 8
    log_info "Increasing number of threads used from 4 to 8 for whisper.cpp..."
    sed -i 's/\/\*\.n_threads         =\*\/\s*std::min(4,/\/\*\.n_threads         =\*\/\ std::min(8,/g' src/whisper.cpp

    if [[ "${BUILD_VINO}" == "1" ]]; then
        log_info "Applying OpenVINO pkg-config patch for Whisper..."
        # Create a patch file that pulls flags through pkg-config
        cat << 'EOF' > patch-openvino.cmake
find_package(PkgConfig REQUIRED)
pkg_check_modules(OV REQUIRED openvino)
pkg_check_modules(TBB REQUIRED tbb)

# Creating a fake CMake target openvino::runtime
if(NOT TARGET openvino::runtime)
    add_library(openvino::runtime INTERFACE IMPORTED)
    target_link_libraries(openvino::runtime INTERFACE ${OV_LIBRARIES} ${TBB_LIBRARIES})
    target_include_directories(openvino::runtime INTERFACE ${OV_INCLUDE_DIRS} ${TBB_INCLUDE_DIRS})
endif()

# Creating a fake CMake target openvino::threading (Fix for new ggml)
if(NOT TARGET openvino::threading)
    add_library(openvino_threading INTERFACE)
    target_link_libraries(openvino_threading INTERFACE ${TBB_LIBRARIES})
    target_include_directories(openvino_threading INTERFACE ${TBB_INCLUDE_DIRS})
    add_library(openvino::threading ALIAS openvino_threading)
endif()

# Creating a fake CMake target TBB::tbb
if(NOT TARGET TBB::tbb)
    add_library(TBB::tbb INTERFACE IMPORTED)
    target_link_libraries(TBB::tbb INTERFACE ${TBB_LIBRARIES})
    target_include_directories(TBB::tbb INTERFACE ${TBB_INCLUDE_DIRS})
endif()

# Creating a fake CMake target OpenCL::OpenCL (Required by ggml-openvino)
if(NOT TARGET OpenCL::OpenCL)
    add_library(OpenCL_cl INTERFACE)
    target_link_libraries(OpenCL_cl INTERFACE OpenCL)
    add_library(OpenCL::OpenCL ALIAS OpenCL_cl)
endif()

# Globally override find_package for OpenVINO so it satisfies components
macro(find_package name)
    if("${name}" STREQUAL "OpenVINO")
        set(OpenVINO_FOUND ON)
        set(OpenVINO_Runtime_FOUND ON)
        set(OpenVINO_Threading_FOUND ON)
        set(OpenVINO_DIR "STUB")
    else()
        _find_package(${ARGV})
    endif()
endmacro()
EOF

        # implement the patch in the VERY ROOT of the project (the main CMakeLists.txt) on the first line
        sed -i '1i include("${CMAKE_CURRENT_SOURCE_DIR}/patch-openvino.cmake")' CMakeLists.txt

        # Cut the TBBConfig hardcode from all ggml subfolders
        find ggml/ -name "CMakeLists.txt" -exec sed -i 's|include(.*TBBConfig.cmake")|# cut|g' {} +
    else
        log_info "OpenVINO is disabled. Skipping patch."
    fi

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-D__TBB_DYNAMIC_LOAD_ENABLED=0 -DOPENVINO_STATIC_LIBRARY"

    mkdir build && cd build

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
    sed -i "s|@CFLAGS@|${CFLAGS} ${OPENMP_C}${USELTO}${USELTO_C} $static_flags|g" main-toolchain.cmake
    sed -i "s|@CPPFLAGS@|${CPPFLAGS}|g" main-toolchain.cmake
    sed -i "s|@TRIPLE@|${FFBUILD_TOOLCHAIN}|g" main-toolchain.cmake
    sed -i "s|@CXXFLAGS@|${CXXFLAGS} ${OPENMP_C}${USELTO}${USELTO_C} $static_flags|g" main-toolchain.cmake
    sed -i "s|@LDFLAGS@|${LDFLAGS} ${USELTO}${USELTO_L}|g" main-toolchain.cmake

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$(pwd)/main-toolchain.cmake"
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
        )

    if has_library "vulkan-1"; then
        log_info "Vulkan library detected. Building with Vulkan support..."
        # Create a host toolchain for the shader builder
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
        myconf+=(
            -DGGML_VULKAN=ON
            -DGGML_VULKAN_SHADERS_GEN_TOOLCHAIN="$(pwd)/host-fix-toolchain.cmake"
            -DVulkan_GLSLC_EXECUTABLE="/opt/glslc"
            -DVulkan_INCLUDE_DIR="$FFBUILD_PREFIX/include"
            -DVulkan_LIBRARY="$FFBUILD_PREFIX/lib/libvulkan.${lib_ext}"
            -DGGML_VULKAN_CHECK_RESULTS=OFF
        )
    fi
    if has_library "curl"; then
        log_info "Curl library detected. Building with Curl support..."
        myconf+=(
            -DWHISPER_CURL=ON # to download models
        )
    fi
    if has_library "OpenCL"; then
        log_info "OpenCL library detected. Building with OpenCL support..."
        myconf+=(
            -DGGML_OPENCL=ON
        )
    fi
    if has_library "SDL2"; then
        log_info "SDL2 library detected. Building with SDL2 support..."
        myconf+=(
            -DWHISPER_SDL2=ON # support for libSDL2
        )
    fi
    if has_library "openvino"; then
        log_info "OpenVINO library detected. Building with OpenVINO support..."
        myconf+=(
            -DGGML_OPENVINO=$([ "${BUILD_VINO}" == "1" ] && echo ON || echo OFF)
            -DWHISPER_OPENVINO=$([ "${BUILD_VINO}" == "1" ] && echo ON || echo OFF)
            # -DOpenVINO_DIR="$FFBUILD_PREFIX/lib/cmake"
            -DGGML_OPENVINO_SKIP_TBB_FIND=ON # don't delete
        )
    fi
    if has_library "openblas"; then
        log_info "OpenBLAS library detected. Building with OpenBLAS support..."
        myconf+=(
            -DGGML_BLAS=ON
            -DGGML_BLAS_VENDOR=OpenBLAS
            -DBLAS_LIBRARIES="${FFBUILD_PREFIX}/lib/libopenblas.${lib_ext}"
            -DBLAS_INCLUDE_DIRS="${FFBUILD_PREFIX}/include/openblas"
        )
    fi

    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # Manually cleaning Vulkan/Shaderc artifacts after whisper
    if [[ -f "$INSTALL_ROOT/bin/glslc.exe" ]]; then
        log_info "Final cleanup of Vulkan/Shaderc build tools..."
        find "$INSTALL_ROOT/bin" -name "glslc.exe" -delete
        if [[ "${PREFER_SHARED}" != "1" ]]; then
            find "$INSTALL_ROOT/lib" -name 'libshaderc_shared.dll' -o -name 'libshaderc_shared.dll.a' -delete
            rm -f /opt/glslc
        fi
    fi

    # CMake often saves them as ggml-base.a, and the linker looks for -lggml-base (i.e. libggml-base.a)
    log_info "Fixing library prefixes for MinGW..."
    # CMake often produces 'ggml.a' instead of 'libggml.a'
    find "$INSTALL_ROOT/lib" -name "ggml*.${lib_ext}" -not -name "lib*" -exec bash -c 'mv "$1" "${1%/*}/lib${1##*/}"' -- {} \;
    find "$INSTALL_ROOT/lib" -name "whisper.${lib_ext}" -not -name "lib*" -exec bash -c 'mv "$1" "${1%/*}/lib${1##*/}"' -- {} \;

    if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then
        find /build/$STAGENAME -type f -name "*.${lib_ext}" -printf "%p (%s bytes)\n"
    fi

    local PC_FILE="$PC_DIR/whisper.pc"
    if [[ -f "$PC_FILE" ]]; then
        log_info "Updating $PC_FILE with backend libraries..."
        local GGML_INTERNAL="-lggml-cpu -lggml -lggml-base"
        local SYS_LIBS="-lstdc++ -lsetupapi -lws2_32 -lshlwapi -lbcrypt ${OPENMP_LIB}-pthread"

        sed -i '/^Libs.private:/d' "$PC_FILE"
        echo "Libs.private: ${GGML_INTERNAL} ${SYS_LIBS}" >> "$PC_FILE"
        if [[ "${myconf[@]}" =~ "-DGGML_OPENCL=ON" ]]; then
            sed -i '/^Libs.private:/ s/$/ -lggml-opencl -lOpenCL/' "$PC_FILE"
        fi
        if [[ "${myconf[@]}" =~ "-DGGML_VULKAN=ON" ]]; then
            sed -i '/^Libs.private:/ s/$/ -lggml-vulkan -lshaderc_combined/' "$PC_FILE"
        fi
        if [[ "${myconf[@]}" =~ "-DGGML_BLAS=ON" ]]; then
            sed -i '/^Libs.private:/ s/$/ -lggml-blas/' "$PC_FILE"
        fi
        if [[ "${myconf[@]}" =~ "-DGGML_OPENVINO=ON" ]]; then
            echo "Requires.private: openvino" >> "$PC_FILE"
            sed -i 's/-lggml /-lggml-openvino -lggml /g' "$PC_FILE"
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
