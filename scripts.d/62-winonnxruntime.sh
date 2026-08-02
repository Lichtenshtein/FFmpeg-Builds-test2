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

    export CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -Wa,-mbig-obj"
    export CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -Wa,-mbig-obj"
    export LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}"

    local cmake_args=(
        "-DCMAKE_TOOLCHAIN_FILE=$FFBUILD_CMAKE_TOOLCHAIN"
        "-DCMAKE_INSTALL_PREFIX=$FFBUILD_PREFIX"
        "-DCMAKE_BUILD_TYPE=Release"
        "-DCMAKE_POLICY_DEFAULT_CMP0091=NEW"
        "-Wno-deprecated"

        "-Donnxruntime_USE_AVX=ON"
        "-Donnxruntime_USE_AVX2=ON"
        "-Donnxruntime_USE_AVX512=$([ "${USE_AVX512}" == "1" ] && echo ON || echo OFF)
"

        # Isolation and stabilization under MinGW (getting rid of Abseil crashes)
        "-Donnxruntime_DISABLE_ABSEIL=ON"
        "-Donnxruntime_CROSS_COMPILING=ON"

        # Disable heavy and unnecessary modules for FFmpeg
        "-Donnxruntime_BUILD_UNIT_TESTS=OFF"
        "-Donnxruntime_BUILD_BENCHMARKS=OFF"
        "-Donnxruntime_ENABLE_TRAINING=OFF"
        "-Donnxruntime_ENABLE_TRAINING_APIS=OFF"
        "-Donnxruntime_ENABLE_TRAINING_OPS=OFF"
        "-Donnxruntime_USE_TELEMETRY=OFF"
    )

    local myconf=(
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

    local additional_cmake_defines=""
    for flag in "${cmake_args[@]}"; do
        additional_cmake_defines="${additional_cmake_defines} ${flag}"
    done
    additional_cmake_defines=$(echo "$additional_cmake_defines" | xargs)

    log_info "Running ONNX Runtime build automation wrapper via Python..."

    cd /build/$STAGENAME

    python3 tools/ci_build/build.py \
        "${myconf[@]}" \
        --cmake_extra_defines "${additional_cmake_defines}" || return 1

    cd build/Linux/Release

    mkdir -p "$INSTALL_ROOT/include/onnxruntime" "$INSTALL_ROOT/lib" "$PC_DIR"

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
