#!/bin/bash

SCRIPT_REPO="https://storage.openvinotoolkit.org/repositories/openvino/packages/2026.1/windows/openvino_toolkit_windows_2026.1.0.21367.63e31528c62_x86_64.zip"

ffbuild_depends() {
    echo tbbmalloc
}

ffbuild_enabled() {
    return 1
}

ffbuild_dockerdl() {
    echo "download_file \"$SCRIPT_REPO\" \"openvino.zip\""
    echo "unzip -qq openvino.zip"
    echo "rm -f openvino.zip"
}

ffbuild_dockerbuild() {
    set -e

    local OV_DIR=$(find . -maxdepth 1 -type d -name "*openvino_*" | head -n 1)
    cd "$OV_DIR"

    log_info "Applying deep MinGW fixes to OpenVINO headers..."

    # Replace BOOLEAN with OV_BOOLEAN_TYPE in all C-API header files
    # This will eliminate the conflict with the BYTE BOOLEAN typedef in winnt.h
    find runtime/include/openvino/c -type f -exec sed -i 's/\bBOOLEAN\b/OV_BOOLEAN_TYPE/g' {} +

    # Remove the dangerous define in openvino.h, which we renamed above.
    sed -i '/#define BOOLEAN OV_BOOLEAN/d' runtime/include/openvino/c/openvino.h

    # Fixed duplicate properties (already there)
    sed -i '/OPENVINO_C_VAR(const char\*) ov_property_key_intel_gpu_config_file;/d' runtime/include/openvino/c/gpu/gpu_plugin_properties.h

    mkdir -p "$INSTALL_ROOT"/{include,lib,bin,lib/cmake}
    cp -r runtime/include/* "$INSTALL_ROOT/include/"
    cp -r runtime/bin/intel64/Release/* "$INSTALL_ROOT/bin/"

    mkdir -p "$INSTALL_ROOT/lib/cmake"
    cp -r runtime/cmake/* "$INSTALL_ROOT/lib/cmake/"

    # Copy ALL frontend libraries, otherwise OpenCV won't build.
    find runtime/lib/intel64/Release/ -name "*.lib" | while read -r f; do
        name=$(basename "$f" .lib)
        cp "$f" "$INSTALL_ROOT/lib/lib${name}.a"
        cp "$f" "$INSTALL_ROOT/lib/${name}.lib"
    done

    # TBB (Intel Threading Building Blocks)
    if [ -f "${FFBUILD_PREFIX}/lib/libtbb.a" ]; then
        log_info "Custom static TBB detected. Skipping OpenVINO's bundled TBB to avoid conflicts."
        # Remove TBB from the OpenVINO sources so that CMake doesn't even try to find it there
        rm -rf runtime/3rdparty/tbb
        # Cleaning INSTALL_ROOT from random traces of TBB DLL versions
        rm -f "${INSTALL_ROOT}/bin/tbb"*".dll" || true
        rm -f "${INSTALL_ROOT}/lib/libtbb"*".dll.a" || true
        # Remove CMake configs for TBB from OpenVINO, they lead to DLLs
        rm -f "${INSTALL_ROOT}/lib/cmake/TBB"*".cmake" || true
    else
        # If we don't have own, we'll use what's given to us (but it will be dynamic)
        log_warn "No custom TBB found, using OpenVINO bundled TBB."
        if [[ -d "runtime/3rdparty/tbb" ]]; then
            find runtime/3rdparty/tbb/bin/ -name "*.dll" ! -name "*_debug.dll" -exec cp {} "$INSTALL_ROOT/bin/" \;
            find runtime/3rdparty/tbb/lib/ -name "*.lib" ! -name "*_debug.lib" -exec cp {} "$INSTALL_ROOT/lib/" \;
            find runtime/3rdparty/tbb/lib/cmake/TBB/ -name "*.cmake" -exec cp {} "$INSTALL_ROOT/lib/cmake/" \;
        fi
    fi

    # Massive patch of file paths and types
    find "$INSTALL_ROOT/lib/cmake" -name "*.cmake" -type f -exec sed -i \
        -e "s|runtime/lib/intel64/Release/|lib/lib|g" \
        -e "s|runtime/lib/intel64/Debug/|lib/lib|g" \
        -e "s|runtime/bin/intel64/Release/|bin/|g" \
        -e "s|runtime/bin/intel64/Debug/|bin/|g" \
        -e "s|runtime/include|include|g" \
        -e "s|\.lib|.a|g" \
        -e "s|liblib|lib|g" \
        {} +

    # code to remove the 'd' suffix
    # process both .a and .dll files, as well as text references to configurations
    find "$INSTALL_ROOT/lib/cmake" -name "*.cmake" -type f -exec sed -i \
        -e 's/d\.a/.a/g' -e 's/fronten\.a/frontend.a/g' \
        -e 's/d\.dll/.dll/g' -e 's/fronten\.dll/frontend.dll/g' \
        -e 's/Debug/Release/g' -e 's/DEBUG/RELEASE/g' \
        {} +

    # Removing file existence checks that often break find_package in cross-compilation
    find "$INSTALL_ROOT/lib/cmake" -name "OpenVINOTargets-*.cmake" -exec sed -i '/_cmake_import_check_files_for_.* exists/d' {} +

    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/openvino.pc"
prefix=$FFBUILD_PREFIX
libdir=\${prefix}/lib
includedir=\${prefix}/include
Name: OpenVINO
Description: Intel OpenVINO Runtime
Version: 2026.1.0
Libs: -L\${libdir} -lopenvino_c -lopenvino
Libs.private: -lopenvino_onnx_frontend -lopenvino_pytorch_frontend -lopenvino_tensorflow_frontend -lopenvino_tensorflow_lite_frontend -lopenvino_paddle_frontend -ltbb12 -lstdc++
Cflags: -I\${includedir} -I\${includedir}/openvino
EOF
}

ffbuild_configure() {
    echo --enable-libopenvino
}

ffbuild_unconfigure() {
    echo --disable-libopenvino
}
