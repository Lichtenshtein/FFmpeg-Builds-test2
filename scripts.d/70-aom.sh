#!/bin/bash

SCRIPT_REPO="https://gitlab.com/damian101/aom-psy101.git"
SCRIPT_COMMIT="74890d72b1850fe013ec574d721001f0db8176bb" 

# SCRIPT_REPO="https://github.com/libsdl-org/aom.git"
# SCRIPT_COMMIT="dc0b27cfbc498aa8ecb2fd23c46b2b734314f3ea" 

ffbuild_depends() {
    echo vmaf
    echo zlib
    echo libavif
    echo libjxl
}

ffbuild_enabled() {
    [[ $VARIANT == lgpl* ]] && return 1
    [[ $TARGET == winarm64 ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    log_info "Patching libaom to match VMAF Pointer ABI..."
    # Add an ampersand (&) before cfg in the vmaf_init call
    sed -i 's/if (vmaf_init(vmaf_context, cfg))/if (vmaf_init(vmaf_context, \&cfg))/g' "aom_dsp/vmaf.c"

    # If there is a file with hwy, force it to use the CXX language
    echo "set_target_properties(aom_hwy PROPERTIES LINKER_LANGUAGE CXX)" >> CMakeLists.txt

    mkdir -p _build && cd _build

    local myconf=(
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DENABLE_AVX512=$([ "${USE_AVX512}" == "1" ] && echo ON || echo OFF)
        -DENABLE_EXAMPLES=OFF
        -DENABLE_TESTS=OFF
        -DENABLE_DOCS=OFF
        -DENABLE_TOOLS=OFF
        -DENABLE_TESTDATA=OFF
        -DENABLE_WERROR=OFF
        -DENABLE_CCACHE=ON
        -DENABLE_NASM=ON
        -DCONFIG_TUNE_VMAF=1
        -DCONFIG_AV1_TEMPORAL_DENOISING=1 # def 0
        -DCONFIG_BITRATE_ACCURACY=1 # def 0
        -DCONFIG_SALIENCY_MAP=1 # saliency map based encode tuning for VMAF; def 0
        -DCONFIG_CWG_C013=1 # Support for 7.x and 8.x levels; def 0
        -DCONFIG_TFLITE=0 # tenserflow-lite static; not working
        -DCONFIG_THREE_PASS=0 # Enable three-pass encoding; def 0, try 1?
        -DCONFIG_HIGHWAY=1 # Use Highway for SIMD; def 0 # hwy donored from libjxl
        -DCONFIG_NN_V2=0 # Fully-connected neural nets ver.2; def 0
        -DCONFIG_AV1_DECODER=1
        -DCONFIG_AV1_ENCODER=1
        -DCONFIG_TUNE_BUTTERAUGLI=0 # need libjxl; cut from libjxl code, leads to "undefined reference" errors
        -DCONFIG_LIBYUV=1 # need libavif
        -DCONFIG_PIC=1
        -DCONFIG_RUNTIME_CPU_DETECT=1
        -DCONFIG_AV1_HIGHBITDEPTH=1
        -DCONFIG_WEBM_IO=1
        # Attempting to fix "cannot determine linker language"
        -DCMAKE_CXX_STANDARD=17 
        -DCMAKE_CXX_STANDARD_REQUIRED=ON
    )

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DJXL_STATIC_DEFINE -DHWY_COMPILE_ONLY_STATIC"

    [[ "${USE_AVX512}" != "1" ]] && avx512_flags="-DHWY_DISABLED_TARGETS=0x1F8"

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags $avx512_flags" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    if [[ "${myconf[@]}" =~ "-DCONFIG_LIBYUV=1" ]]; then
        local JXL_LIBS=" libjxl libjxl_cms libhwy"
    fi

    if ! grep -q "libvmaf" "$PC_DIR/aom.pc"; then
        # Remove the old Requires line, if there was one
        sed -i '/^Requires:/d' "$PC_DIR/aom.pc"
        # register deps in Requires.private so that they are linked AFTER -laom
        sed -i "/^Description:/a Requires.private: libvmaf${JXL_LIBS}" "$PC_DIR/aom.pc"
    fi
    sed -i "s|^Cflags:.*|& -I\${includedir}/aom|" "$PC_DIR/aom.pc"
}

ffbuild_configure() {
    echo --enable-libaom
}

ffbuild_unconfigure() {
    echo --disable-libaom
}
