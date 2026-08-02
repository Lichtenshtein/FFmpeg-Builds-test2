#!/bin/bash

SCRIPT_REPO="https://github.com/microsoft/onnxruntime.git"
SCRIPT_COMMIT="86af0f166f80f022e61a03164f2ff7809bf4f7e2"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    cd /build/$STAGENAME

    log_info "${BROOM_MARK} Patching Windows resource files to fix windres syntax errors..."
    if [[ -f "onnxruntime/core/dll/onnxruntime.rc" ]]; then
        sed -i 's|<Winver.h>|<winver.h>|g' onnxruntime/core/dll/onnxruntime.rc
        sed -i 's|<Ntstatus.h>|<ntstatus.h>|g' onnxruntime/core/dll/onnxruntime.rc
        sed -i 's|.*"LegalCopyright".*|            VALUE "LegalCopyright",   "(c) Microsoft Corporation. All rights reserved."|g' onnxruntime/core/dll/onnxruntime.rc
    fi

    log_info "${BROOM_MARK} Patching ONNX Runtime CMake files for CMake 4.4+ compatibility..."
    if [[ -f "cmake/onnxruntime.cmake" ]]; then
        # Remove lines related to the /DELAYLOAD and target_link_options bug on line 341
        sed -i 's/if (WIN32 AND NOT CMAKE_CXX_STANDARD_LIBRARIES MATCHES kernel32.lib)/if (FALSE)/g' cmake/onnxruntime.cmake
        sed -i 's|target_link_options(onnxruntime PRIVATE /DELAYLOAD:# target_link_options(onnxruntime PRIVATE /DELAYLOAD:|g' cmake/onnxruntime.cmakecmake/onnxruntime.cmake
    fi

    log_info "${BROOM_MARK} Patching ONNX Runtime C++ source files for MinGW compatibility..."
    # Fixing a SAL macro conflict in onnxruntime_c_api.h to use native macros from sal.h
    if [[ -f "include/onnxruntime/core/session/onnxruntime_c_api.h" ]]; then
        sed -i '/#define _Check_return_/i #ifndef __MINGW32__' include/onnxruntime/core/session/onnxruntime_c_api.h
        sed -i '/#define _Outptr_result_buffer_maybenull_(X)/a #endif \/* __MINGW32__ *\/' include/onnxruntime/core/session/onnxruntime_c_api.h
    fi
    if [[ -f "onnxruntime/core/mlas/lib/mlasi.h" ]]; then
        sed -i 's/#ifdef _MSC_VER/#if defined(_MSC_VER) || defined(__MINGW32__)/g' onnxruntime/core/mlas/lib/mlasi.h
    fi

    log_info "${BROOM_MARK} Isolating MSVC warning flags under if(MSVC) blocks..."
    if [[ -f "cmake/CMakeLists.txt" ]]; then
        sed -i 's/if (WIN32)/if (MSVC)/g' cmake/CMakeLists.txt
    elif [[ -f "CMakeLists.txt" ]]; then
        sed -i 's/if (WIN32)/if (MSVC)/g' CMakeLists.txt
    fi
    if [[ -f "cmake/onnxruntime_mlas.cmake" ]]; then
        sed -i 's/if (WIN32)/if (MSVC)/g' cmake/onnxruntime_mlas.cmake
    fi
    if [[ -f "cmake/onnxruntime_providers_nv.cmake" ]]; then
        sed -i 's/if (WIN32)/if (MSVC)/g' cmake/onnxruntime_providers_nv.cmake
    fi
    find . \( -name "CMakeLists.txt" -o -name "*.cmake" \) -type f -exec sed -i \
        -e 's|"/wd[0-9]*"|""|g' \
        -e 's|"/w1[0-9]*"|""|g' \
        -e 's|/wd[0-9]*| |g' \
        -e 's|/w1[0-9]*| |g' \
        {} +

    log_info "${BROOM_MARK} Patching status.h to include winerror.h for MinGW..."
    local status_header=""
    if [[ -f "include/onnxruntime/core/common/status.h" ]]; then
        status_header="include/onnxruntime/core/common/status.h"
    elif [[ -f "onnxruntime/core/common/status.h" ]]; then
        status_header="onnxruntime/core/common/status.h"
    fi
    if [[ -n "$status_header" ]]; then
        sed -i '/winerror.h/d' "$status_header"
        sed -i '/#ifdef _WIN32/i #if defined(__MINGW32__)\n#ifndef WIN32_LEAN_AND_MEAN\n#define WIN32_LEAN_AND_MEAN\n#endif\n#include <windows.h>\n#endif' "$status_header"
    fi

    log_info "${BROOM_MARK} Fixing MLAS assembly macro syntax for Windows PE-COFF (MinGW)..."
    if [[ -f "onnxruntime/core/mlas/lib/x86_64/asmmacro.h" ]]; then
        sed -i 's|\.type[[:space:]]*\\FunctionName\\(),@function||g' onnxruntime/core/mlas/lib/x86_64/asmmacro.h
    fi
    if [[ -f "onnxruntime/core/mlas/lib/x86/asmmacro.h" ]]; then
        sed -i 's|\.type[[:space:]]*\\FunctionName\\(),@function||g' onnxruntime/core/mlas/lib/x86/asmmacro.h
    fi

    log_info "${BROOM_MARK} Removing Linux-specific .hidden pseudo-ops from assembly files..."
    if [[ -d "onnxruntime/core/mlas/lib/x86_64" ]]; then
        find onnxruntime/core/mlas/lib/x86_64/ -type f \( -name "*.S" -o -name "*.h" \) -exec sed -i 's/^[[:space:]]*\.hidden[[:space:]].*//g' {} +
    fi

    log_info "${BROOM_MARK} Disabling Intel AMX kernels in MLAS..."
    if [[ -f "cmake/onnxruntime_mlas.cmake" ]]; then
        sed -i 's|${MLAS_SRC_DIR}/qgemm_kernel_amx.cpp||g' cmake/onnxruntime_mlas.cmake
        sed -i 's|${MLAS_SRC_DIR}/amd64/QgemmU8S8KernelAmx.asm||g' cmake/onnxruntime_mlas.cmake
        sed -i 's/if(NOT APPLE)/if(FALSE)/g' cmake/onnxruntime_mlas.cmake
    fi

    export CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -Wa,-mbig-obj"
    export CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -Wa,-mbig-obj"
    export LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}"

    local cmake_args=(
        "CMAKE_TOOLCHAIN_FILE=$FFBUILD_CMAKE_TOOLCHAIN"
        "CMAKE_INSTALL_PREFIX=$FFBUILD_PREFIX"
        "CMAKE_BUILD_TYPE=Release"

        "CMAKE_COMPILE_WARNING_AS_ERROR=OFF"
        "CMAKE_WARN_DEPRECATED=OFF"
        "CMAKE_POLICY_DEFAULT_CMP0091=NEW"
        "CMAKE_POLICY_DEFAULT_CMP0169=OLD"
        "CMAKE_POLICY_DEFAULT_CMP0146=OLD"

        "onnxruntime_USE_SVE=OFF"
        "onnxruntime_USE_KLEIDIAI=OFF"

        # "Iconv_IS_BUILT_IN=TRUE"
        # "CMAKE_DISABLE_FIND_PACKAGE_Iconv=ON"
        # "CMAKE_DISABLE_FIND_PACKAGE_LibIconv=ON"

        "onnxruntime_USE_AVX=ON"
        "onnxruntime_USE_AVX2=ON"
        "onnxruntime_USE_AVX512=$([ "${USE_AVX512}" == "1" ] && echo ON || echo OFF)"

        # Isolation and stabilization under MinGW (getting rid of Abseil crashes)
        "onnxruntime_DISABLE_ABSEIL=ON"
        "onnxruntime_CROSS_COMPILING=ON"

        # Disable heavy and unnecessary modules for FFmpeg
        "onnxruntime_BUILD_UNIT_TESTS=OFF"
        "onnxruntime_BUILD_BENCHMARKS=OFF"
        "onnxruntime_ENABLE_TRAINING=OFF"
        "onnxruntime_ENABLE_TRAINING_APIS=OFF"
        "onnxruntime_ENABLE_TRAINING_OPS=OFF"
        "onnxruntime_USE_TELEMETRY=OFF"
    )

    if has_library "openvino"; then
        log_info "OpenVINO library detected. Building with OpenVINO support..."
        cmake_args+=( "onnxruntime_USE_OPENVINO=ON" )
    fi

    local myconf=(
        --build_dir build
        --allow_running_as_root
        --config Release
        --update
        --build
        --parallel
        --skip_submodule_sync
        --skip_tests
        --compile_no_warning_as_error
    )

    if [[ "${PREFER_SHARED}" == "1" ]]; then
        myconf+=( --build_shared_lib )
    fi

    log_info "Running ONNX Runtime build automation wrapper via Python..."

    mkdir -p build/Release "$INSTALL_ROOT/include/onnxruntime" "$INSTALL_ROOT/lib" "$PC_DIR"

    python3 tools/ci_build/build.py \
        "${myconf[@]}" \
        --cmake_extra_defines "${cmake_args[@]}" || return 1

    cd build/Release

    # log_info "Deploying ONNX Runtime headers and libraries..."

    # cp -r "$ROOT_DIR/include/onnxruntime/core/session/onnxruntime_c_api.h" "$INSTALL_ROOT/include/onnxruntime/"

    # if [[ "$PREFER_SHARED" == "1" ]]; then
        # cp "libonnxruntime.dll" "$INSTALL_ROOT/bin/"
        # cp "libonnxruntime.dll.a" "$INSTALL_ROOT/lib/"
    # else
        # cp "libonnxruntime.a" "$INSTALL_ROOT/lib/"
    # fi

    if [[ ! -f "${PC_DIR}/onnxruntime.p" ]]; then
        cat <<EOF > "$PC_DIR/onnxruntime.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: onnxruntime
Description: ONNX Runtime cross-platform, high performance ML inferencing accelerator
Version: 1.28.0
Libs: -L\${libdir} -lonnxruntime
Libs.private: -lshlwapi -luser32 -ladvapi32 -lws2_32 -lbcrypt
Cflags: -I\${includedir}/onnxruntime
EOF
    fi
}

ffbuild_configure() {
    echo --enable-libonnxruntime
}
