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

    log_info "${BROOM_MARK} Patching ONNX Runtime CMake files for CMake 4.4+ compatibility..."
    if [[ -f "cmake/onnxruntime.cmake" ]]; then
        # Remove lines related to the /DELAYLOAD and target_link_options bug on line 341
        sed -i 's/if (WIN32 AND NOT CMAKE_CXX_STANDARD_LIBRARIES MATCHES kernel32.lib)/if (FALSE)/g' cmake/onnxruntime.cmake
        sed -i 's|target_link_options(onnxruntime PRIVATE /DELAYLOAD:# target_link_options(onnxruntime PRIVATE /DELAYLOAD:|g' cmake/onnxruntime.cmakecmake/onnxruntime.cmake
    fi

    export CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -Wa,-mbig-obj"
    export CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -Wa,-mbig-obj"
    export LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}"

    local cmake_args=(
        "CMAKE_TOOLCHAIN_FILE=$FFBUILD_CMAKE_TOOLCHAIN"
        "CMAKE_INSTALL_PREFIX=$FFBUILD_PREFIX"
        "CMAKE_BUILD_TYPE=Release"

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

    local myconf=(
        --build_dir build
        --allow_running_as_root
        --config Release
        --update
        --build
        --parallel
        --skip_submodule_sync
        --skip_tests
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
