#!/bin/bash

SCRIPT_REPO="https://github.com/openvinotoolkit/openvino.git"
SCRIPT_COMMIT="3dd09b2f61093429aa0ac963842fc1858cae3643"

ffbuild_depends() {
    echo tbbmalloc
    echo opencl
    echo zlib
    # echo opencv # cross dep with opencv itself which compiled after Vino
}

ffbuild_enabled() {
    [[ "$BUILD_VINO" == "1" ]] && return 0
    return 1
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-submodule-clone"
    # can probably clean more from /thirdparty folder
    echo "rm -rf .github samples \
tests \
src/core/tests \
src/tests \
src/plugins/intel_npu/tests \
src/plugins/intel_gpu/tests \
src/plugins/intel_cpu/tests \
\
src/plugins/intel_npu/thirdparty/yaml-cpp/test \
\
src/plugins/intel_gpu/thirdparty/onednn_gpu/examples \
src/plugins/intel_gpu/thirdparty/onednn_gpu/doc \
src/plugins/intel_gpu/thirdparty/onednn_gpu/tests \
\
src/plugins/intel_cpu/thirdparty/ComputeLibrary/tests \
src/plugins/intel_cpu/thirdparty/ComputeLibrary/third_party/kleidiai/third_party \
src/plugins/intel_cpu/thirdparty/ComputeLibrary/third_party/kleidiai/test \
src/plugins/intel_cpu/thirdparty/ComputeLibrary/third_party/kleidiai/benchmark \
\
src/plugins/intel_cpu/thirdparty/libxsmm/tests \
src/plugins/intel_cpu/thirdparty/libxsmm/samples \
src/plugins/intel_cpu/thirdparty/libxsmm/documentation \
\
src/plugins/intel_cpu/thirdparty/onednn/tests \
src/plugins/intel_cpu/thirdparty/onednn/examples \
src/plugins/intel_cpu/thirdparty/onednn/doc \
\
thirdparty/flatbuffers/flatbuffers/benchmarks \
thirdparty/flatbuffers/flatbuffers/tests \
\
thirdparty/gtest/gtest/googlemock \
thirdparty/gtest/gtest/googletest \
\
thirdparty/json/nlohmann_json/tests \
thirdparty/json/nlohmann_json/docs/usages/ios.png \
thirdparty/json/nlohmann_json/docs/usages/macos.png \
thirdparty/json/nlohmann_json/docs/avatars.png \
thirdparty/json/nlohmann_json/docs/json.gif \
\
thirdparty/ocl/clhpp_headers/tests \
thirdparty/ocl/clhpp_headers/external/CMock/test/iar \
\
thirdparty/onnx/onnx/docs \
thirdparty/onnx/onnx/onnx/test \
thirdparty/onnx/onnx/onnx/backend/test \
\
thirdparty/protobuf/protobuf/csharp \
thirdparty/protobuf/protobuf/java \
thirdparty/protobuf/protobuf/objectivec/Tests \
thirdparty/protobuf/protobuf/third_party/googletest \
\
thirdparty/pugixml/docs \
thirdparty/pugixml/tests \
\
thirdparty/snappy/testdata \
thirdparty/snappy/third_party \
\
thirdparty/zlib/zlib/contrib"
}

ffbuild_dockerbuild() {
    set -e

    log_info "Disabling samples and snippets subdirectories precisely..."
    sed -i '/ov_mark_target_as_cc(${TARGET_NAME})/a return()' docs/snippets/CMakeLists.txt
    sed -i 's/^[[:space:]]*add_subdirectory(samples)/# add_subdirectory(samples)/g' CMakeLists.txt

    log_info "Fixing case-sensitive Shlwapi library names for Linux host..."
    sed -i 's/\bShlwapi\b/shlwapi/g' src/common/util/CMakeLists.txt

    log_info "Fixing MSVC -EP flag to GCC -E -P for Intel GPU CM codegen..."
    find src/plugins/intel_gpu/src/graph/impls/ -name "CMakeLists.txt" -type f -exec sed -i 's/-EP/-E\ -P/g' {} +

    log_info "Neutralizing forced -Werror in Intel GPU root CMakeLists..."
    sed -i 's/ov_add_compiler_flags(-Werror)/# ov_add_compiler_flags(-Werror)/g' src/plugins/intel_gpu/CMakeLists.txt

    log_info "Completely neutralizing template_extension build via early return..."
    echo "return()" | cat - src/core/template_extension/CMakeLists.txt > temp && mv temp src/core/template_extension/CMakeLists.txt

    log_info "${BROOM_MARK} Patching OpenVINO and submodules CMake scripts to suppress warnings..."
    find . -name "CMakeLists.txt" -o -name "*.cmake" | xargs sed -i 's/-Wformat/-Wno-format/g' 2>/dev/null || true
    find . -name "CMakeLists.txt" -o -name "*.cmake" | xargs sed -i 's/-Wundef/-Wno-undef/g' 2>/dev/null || true

    export TBBROOT="$FFBUILD_PREFIX"

    mkdir build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        # Disable ALL frontends
        -DENABLE_OV_IR_FRONTEND=ON # leave only the basic IR XML/BIN parser
        -DENABLE_OV_ONNX_FRONTEND=OFF
        -DENABLE_OV_PADDLE_FRONTEND=OFF
        -DENABLE_OV_TF_FRONTEND=OFF
        -DENABLE_OV_TF_LITE_FRONTEND=OFF
        -DENABLE_OV_PYTORCH_FRONTEND=OFF
        -DENABLE_OV_JAX_FRONTEND=OFF
        # Disable plugins and heavy dependencies
        -DENABLE_INTEL_CPU=ON # leave only the CPU plugin
        -DENABLE_INTEL_GPU=OFF # GPU requires OpenCL/Vulkan headers; it's for integrated (iGPU) and discrete (dGPU) Intel graphics cards; build works
        -DENABLE_INTEL_NPU=OFF
        -DENABLE_HETERO=OFF
        -DENABLE_MULTI=OFF
        -DENABLE_AUTO=OFF
        -DENABLE_AUTO_BATCH=OFF
        -DENABLE_PROXY=OFF
        -DENABLE_TEMPLATE=OFF
        -DENABLE_OPENCV=OFF # OpenCV samples; provides -lprotobuf, but goes after
        -DENABLE_SYSTEM_PUGIXML=OFF # ON
        -DENABLE_SYSTEM_PROTOBUF=OFF # OFF; for ONNX, PaddlePaddle, TensorFlow
        -DENABLE_SYSTEM_FLATBUFFERS=OFF # ON; for Tensorflow Lite frontend
        -DENABLE_SYSTEM_OPENCL=ON # ON; use OpenCL installed on the system
        # Size and build optimizations
        -DENABLE_JS=OFF
        -DENABLE_SAMPLES=OFF
        -DENABLE_TESTS=OFF
        -DENABLE_FUNCTIONAL_TESTS=OFF
        -DENABLE_SNIPPETS_LIBXSMM_TPP=OFF
        -DENABLE_PYTHON=OFF
        -DENABLE_WHEEL=OFF
        -DENABLE_CLANG_FORMAT=OFF
        -DENABLE_PROFILING_ITT=OFF
        # hardware instructions
        -DENABLE_SSE42=ON
        -DENABLE_AVX2=ON
        -DENABLE_AVX512F=$([ "${USE_AVX512}" == "1" ] && echo ON || echo OFF)
        -DENABLE_FASTER_BUILD=OFF # OFF; precompiled headers and unity build
        # cross-compilation
        -DENABLE_API_VALIDATOR=OFF # search Windows SDK / apivalidator.exe
        -DENABLE_INTEL_ITT=OFF # removes the binding to the Windows ITT/VTune API
        -DENABLE_CPPLINT=OFF # doesn't search for Python linters
        -DENABLE_NCC_STYLE=OFF # disables OpenVINO style checking
        # Additional
        -DCMAKE_CXX_STANDARD=20
        -DCMAKE_CXX_STANDARD_REQUIRED=ON
        -DCMAKE_COMPILE_WARNING_AS_ERROR=OFF
    )

    if has_library "tbbmalloc"; then
        log_info "TBB library detected. Building with TBB support..."
        myconf+=(
            -DTHREADING=$([ "${USE_OPENMP}" == "1" ] && echo OMP || echo TBB)
            -DENABLE_SYSTEM_TBB=$([ "${USE_OPENMP}" == "1" ] && echo OFF || echo ON)
            -DENABLE_TBBBIND_2_5=OFF # Disable the hybrid scheduler
            -DTBB_DIR="${FFBUILD_PREFIX}/lib/cmake/TBB"
        )
    elif [[ "${USE_OPENMP}" == "1" ]]; then
        log_info "Enabling OpenMP threading..."
        myconf+=(
            -DTHREADING=OMP
        )
    fi

    # will not work for submodules, likely same appends to lto flags
    local NO_WARNS="-Wno-undef -Wno-format -Wno-format-extra-args"

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-D__TBB_DYNAMIC_LOAD_ENABLED=0" && self_static_flags="-DOPENVINO_STATIC_LIBRARY"

    [[ "${USE_LTO}" == "1" ]] && LTO_FLAGS="-Wno-odr -Wa,-mbig-obj -fno-lto-odr-type-merging"

    CFLAGS="$CFLAGS $CPPFLAGS ${OPENMP_C}${USELTO}${USELTO_C} ${NO_WARNS} $LTO_FLAGS $self_static_flags" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${OPENMP_C}${USELTO}${USELTO_C} ${NO_WARNS} $LTO_FLAGS $static_flags $self_static_flags -DWINAPI_PARTITION_SYSTEM=1" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L} $LTO_FLAGS -Wl,--allow-multiple-definition" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    log_info "Moving and restructuring OpenVINO layout..."

    # need to turn include/c/ into include/openvino/c/
    mkdir -p "${INSTALL_ROOT}/include/openvino"

    # Move the internal folders (c, core, frontend, op, opsets, pass, runtime) to the openvino folder
    find "${INSTALL_ROOT}/runtime/include/" -mindepth 1 -maxdepth 1 | while read -r src_dir; do
        mv "$src_dir" "${INSTALL_ROOT}/include/"
    done

    if [[ "${PREFER_SHARED}" != "1" ]]; then
        # collect all static .a libraries scattered across folders into a single lib
        mkdir -p "${INSTALL_ROOT}/lib"
        find "${INSTALL_ROOT}/runtime/lib" -name "*.a" -exec mv {} "${INSTALL_ROOT}/lib/" \;

        # clean LTO sections from static libraries to reduce the size from 1.7 GB to ~100 MB
        log_info "Stripping heavy GCC LTO sections from .a files to optimize size..."
        find "${INSTALL_ROOT}" -name "*.a" | while read -r LIB_FILE; do
            ${OBJCOPY} --remove-section=.gnu.lto_* "$LIB_FILE" || true
        done
    fi

    # Move the CMake files to the correct default directory
    mkdir -p "${INSTALL_ROOT}/lib/cmake"
    mv "${INSTALL_ROOT}/runtime/cmake" "${INSTALL_ROOT}/lib/"
    rm -rf "${INSTALL_ROOT}/runtime"

    # Patching relative paths inside migrated CMake files
    log_info "Performing massive absolute path patching inside OpenVINO CMake files..."
    find "${INSTALL_ROOT}/lib/cmake" -name "*.cmake" -type f | while read -r CMAKE_FILE; do
        # fixt PACKAGE_PREFIX_DIR to absolute cross-compilation root
        sed -i 's|get_filename_component(PACKAGE_PREFIX_DIR "${CMAKE_CURRENT_LIST_DIR}/../../" ABSOLUTE)|set(PACKAGE_PREFIX_DIR "/opt/ffbuild")|g' "$CMAKE_FILE"

        # Links to path checks if ACL (ARM Compute Library) or onednn_gpu_lib_root is called
        sed -i 's|"${PACKAGE_PREFIX_DIR}/runtime/lib/intel64/Release"|"/opt/ffbuild/lib"|g' "$CMAKE_FILE"

        # remove the relative prefix calculation in Targets so that it doesn't overwrite paths
        sed -i 's|get_filename_component(_IMPORT_PREFIX "${_IMPORT_PREFIX}" PATH)|# Absolute path used|g' "$CMAKE_FILE"

        # replace all of Intel's tricky relative constructs with a hard absolute path
        sed -i 's|"\${_IMPORT_PREFIX}/runtime/lib/intel64/Release/|"/opt/ffbuild/lib/|g' "$CMAKE_FILE"
        sed -i 's|"\${_IMPORT_PREFIX}/runtime/lib/intel64/Debug/|"/opt/ffbuild/lib/|g' "$CMAKE_FILE"
        sed -i 's|"\${_IMPORT_PREFIX}/runtime/lib/|"/opt/ffbuild/lib/|g' "$CMAKE_FILE"
        sed -i 's|"\${_IMPORT_PREFIX}/runtime/include|"/opt/ffbuild/include/openvino|g' "$CMAKE_FILE"
        sed -i 's|"\${_IMPORT_PREFIX}/runtime/bin/|"/opt/ffbuild/bin/|g' "$CMAKE_FILE"

        # Fixing extensions and structures for GCC/MinGW statics
        sed -i 's|\.lib|.a|g' "$CMAKE_FILE"
        sed -i 's|liblib|lib|g' "$CMAKE_FILE"
        sed -i 's|/intel64/Release/||g' "$CMAKE_FILE"
        sed -i 's|/intel64/Debug/||g' "$CMAKE_FILE"
        # synchronize debug suffixes if they slipped through somewhere
        sed -i -e 's/d\.a/.a/g' -e 's/fronten\.a/frontend.a/g' "$CMAKE_FILE"
        sed -i -e 's/Debug/Release/g' -e 's/DEBUG/RELEASE/g' "$CMAKE_FILE"
    done

    # log_debug "Inspecting generated OpenVINO CMake configuration files:"
    if [ -f "${INSTALL_ROOT}/lib/cmake/OpenVINOConfig.cmake" ]; then
        log_info "--- Content of OpenVINOConfig.cmake ---"
        while IFS= read -r line; do
            log_debug "  $line"
        done < "${INSTALL_ROOT}/lib/cmake/OpenVINOConfig.cmake"
    else
        log_error "OpenVINOConfig.cmake NOT FOUND in ${INSTALL_ROOT}/lib/cmake/"
    fi
    # if [ -f "${INSTALL_ROOT}/lib/cmake/OpenVINOTargets-release.cmake" ]; then
        # log_info "--- Content of OpenVINOTargets-release.cmake ---"
        # cat "${INSTALL_ROOT}/lib/cmake/OpenVINOTargets-release.cmake" >&2
    # fi

    # Fix for old FFmpeg checks (Inference Engine C-API Wrapper)
    # Redirect the old c_api/ie_c_api.h call to the modern openvino/c/openvino.h
    if [[ ! -f "$INSTALL_ROOT/include/c_api/ie_c_api.h" ]]; then
    mkdir -p "$INSTALL_ROOT/include/c_api"
    cat <<EOF > "$INSTALL_ROOT/include/c_api/ie_c_api.h"
#ifndef COMPAT_IE_C_API_H
#define COMPAT_IE_C_API_H
#include <openvino/c/openvino.h>

static __attribute__((unused)) const char* ie_c_api_version(void) { 
    return "${VER_FULL}"; 
}
#endif
EOF
    fi

    # Create an empty dummy library, libinference_engine_c_api.a,
    # to satisfy the FFmpeg linker's hard fallback (-linference_engine_c_api)
    log_info "Creating inference_engine_c_api fallback stub for FFmpeg configure..."
    rm -f "$INSTALL_ROOT/lib/libinference_engine_c_api.a"
    ar rcs "$INSTALL_ROOT/lib/libinference_engine_c_api.a"

    # collect all libs
    log_info "Dynamically collecting installed OpenVINO libraries..."

    # collect the main interface libs, which should be first in the linking queue
    local CORE_LIBS=""
    for main_lib in libopenvino.a libopenvino_c.a; do
        if [ -f "${INSTALL_ROOT}/lib/${main_lib}" ]; then
            CORE_LIBS="${CORE_LIBS} -l${main_lib%.a}"
            CORE_LIBS="${CORE_LIBS#lib}" # remove the lib prefix for the -l flag
        fi
    done
    # Fix the line (convert -llibopenvino to -lopenvino)
    CORE_LIBS=$(echo "$CORE_LIBS" | sed 's/-llib/-l/g')

    # collect all the remaining internal OpenVINO components, excluding those already added and third-party ones (tbb, pugixml)
    local COMPONENT_LIBS=$(find "${INSTALL_ROOT}/lib" -name "libopenvino_*.a" | sed "s|.*/lib\(.*\)\.a|-l\1|" | xargs)

    # Force adding pugixml if it was built inside OpenVINO
    local PUGI_LIB=""
    [ -f "${INSTALL_ROOT}/lib/libpugixml.a" ] && PUGI_LIB="-lpugixml"

    local INTER_LIB=""
    [ -f "${INSTALL_ROOT}/lib/libinference_engine_c_api.a" ] && INTER_LIB="-linference_engine_c_api"

    log_info "Generated Libs sequence: ${CORE_LIBS} ${INTER_LIB} ${COMPONENT_LIBS} ${PUGI_LIB}"

    log_info "Generating openvino.pc file for pkg-config..."
    mkdir -p "${PC_DIR}"
    cat <<EOF > "${PC_DIR}/openvino.pc"
prefix=${FFBUILD_PREFIX}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: OpenVINO
Description: Intel OpenVINO Runtime Static Library
Version: ${VER_FULL}
Cflags: -I\${includedir} -I\${includedir}/openvino $static_flags $self_static_flags
Libs: -L\${libdir} ${CORE_LIBS} ${INTER_LIB} ${COMPONENT_LIBS} ${PUGI_LIB}
Libs.private: -ltbb -lshlwapi -lsetupapi -lws2_32 -lbcrypt
EOF
}

ffbuild_configure() {
    echo --enable-libopenvino
}

ffbuild_unconfigure() {
    echo --disable-libopenvino
}
