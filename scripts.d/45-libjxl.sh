#!/bin/bash

SCRIPT_REPO="https://github.com/libjxl/libjxl.git"
SCRIPT_COMMIT="196a43d996aa6ed33ebf98812a7c6d43b2b6d01b"

ffbuild_depends() {
    echo brotli
    echo lcms2
    echo giflib
    echo libjpeg-turbo
    echo libpng
    echo libavif
    echo libwebp
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .

    # echo "git-submodule-clone"
    echo "mkdir -p testdata"
    echo "git-mini-clone \"https://github.com/google/highway.git\" \"master\" third_party/highway"
    echo "git-mini-clone \"https://github.com/webmproject/sjpeg.git\" \"main\" third_party/sjpeg"
    echo "rm -rf \
third_party/sjpeg/tests \
third_party/highway/g3doc \
third_party/highway/hwy/tests \
tools/benchmark"

    # because it constantly fails to patch it normally
    local COMPONENT_NAME="libjxl"
    local PATCHES_DIR="${PATCHES_DIR}"
    local CUSTOM_CMAKELISTS="${PATCHES_DIR}/${COMPONENT_NAME}/CMakeLists.txt"

    if [[ -f "$CUSTOM_CMAKELISTS" ]]; then
        log_info "Replacing CMakeLists.txt with custom version from patches..."
        echo "cp -rf${OP_V} '$CUSTOM_CMAKELISTS' './third_party/highway/CMakeLists.txt'"
    else
        log_warn "Custom CMakeLists.txt not found at $CUSTOM_CMAKELISTS. Using default."
    fi
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build "$PC_DIR" && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DJPEGXL_STATIC=$([ "${PREFER_SHARED}" == "1" ] && echo OFF || echo ON)

        -DJPEGXL_EMSCRIPTEN=OFF
        -DJPEGXL_ENABLE_BENCHMARK=OFF
        -DJPEGXL_ENABLE_DEVTOOLS=OFF
        -DJPEGXL_ENABLE_EXAMPLES=OFF
        -DJPEGXL_ENABLE_DOXYGEN=OFF
        -DJPEGXL_ENABLE_JNI=OFF
        -DJPEGXL_ENABLE_MANPAGES=OFF
        -DJPEGXL_ENABLE_PLUGINS=OFF
        -DJPEGXL_ENABLE_SKCMS=OFF # ON; Google LCMS alternative
        -DJPEGXL_ENABLE_TOOLS=OFF
        -DJPEGXL_ENABLE_VIEWERS=OFF
        -DJPEGXL_ENABLE_WASM_THREADS=ON
        -DJPEGXL_FORCE_SYSTEM_HWY=OFF
        # -DJPEGXL_ENABLE_LTO=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DBUILD_TESTING=OFF
    )

    if has_library "brotlidec"; then
        log_info "Brotli library detected. Building with Brotli support..."
        myconf+=( -DJPEGXL_FORCE_SYSTEM_BROTLI=ON )
    fi
    if has_library "lcms2"; then
        log_info "Lcms2 library detected. Building with Lcms2 support..."
        myconf+=( -DJPEGXL_FORCE_SYSTEM_LCMS2=ON -DJPEGXL_ENABLE_SKCMS=OFF )
        local LCMS_PC="lcms2 libjxl_cms"
    else
        log_info "Building with google's Scms support..."
        myconf+=( -DJPEGXL_ENABLE_SKCMS=ON ) # Google LCMS alternative 
    fi
    if has_library "png"; then
        log_info "PNG library detected. Building with PNG support..."
        myconf+=( -DJPEGXL_BUNDLE_LIBPNG=OFF )
    else
        myconf+=( -DJPEGXL_BUNDLE_LIBPNG=ON )
    fi

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DJXL_STATIC_DEFINE"

    if [[ $TARGET == linux* ]]; then
        # our glibc is too old(<2.25), and their detection fails for some reason
        export CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}"
        export CXXFLAGS="$CXXFLAGS ${USELTO}${USELTO_C} -DVQSORT_GETRANDOM=0 -DVQSORT_SECURE_SEED=0"
        export LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}"
    elif [[ $TARGET == win* ]]; then
        # Fix AVX2 related crash due to unaligned stack memory
        [[ "${USE_LTO}" == "1" ]] && \
            STACK_FLAGS="-mstackrealign -mincoming-stack-boundary=4" || \
            STACK_FLAGS="-Wa,-muse-unaligned-vector-move"
        export CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags ${STACK_FLAGS} -DHWY_COMPILE_ALL_ATTRIBUTES"
        export CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags ${STACK_FLAGS} -DHWY_COMPILE_ALL_ATTRIBUTES"
        export LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}"
    fi

    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local PC_FILE="$PC_DIR/libjxl_cms.pc"

    if [[ "${myconf[@]}" =~ "-DJPEGXL_FORCE_SYSTEM_LCMS2=ON" ]]; then
        if ! grep -q "Requires.private:" "$PC_FILE"; then
            sed -i "/^Libs:/i Requires.private: ${LCMS_PC} libhwy" "$PC_FILE"
        elif ! grep -q "Requires.private:.*lcms" "$PC_FILE"; then
            sed -i "/^Requires.private:/s/$/ ${LCMS_PC} libhwy/" "$PC_FILE"
        fi
    fi

    sed -i 's/Libs:/Libs: -lhwy/' "$PC_DIR/libjxl.pc"
    sed -i "s|^Cflags:.*|& -I\${includedir}/jxl|" "$PC_DIR/libjxl_threads.pc"
    sed -i "s|^Cflags:.*|& -I\${includedir}/jxl|" "$PC_DIR/libjxl.pc"
    sed -i "s|^Cflags:.*|& -I\${includedir}/jxl|" "$PC_DIR/libjxl_cms.pc"
    sed -i "s|^Cflags:.*|& -I\${includedir}/hwy|" "$PC_DIR/libhwy.pc"
}

ffbuild_cppflags() {
    echo "$static_flags"
}

ffbuild_configure() {
    echo --enable-libjxl
}

ffbuild_unconfigure() {
    echo --disable-libjxl
}
