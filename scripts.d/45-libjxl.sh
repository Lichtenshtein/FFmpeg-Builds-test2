#!/bin/bash

SCRIPT_REPO="https://github.com/libjxl/libjxl.git"
SCRIPT_COMMIT="15c547544296c29a2da931e9112e3c45e3972ef6"

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
    echo "git-submodule-clone"
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DJPEGXL_STATIC=$([ "${PREFER_SHARED}" == "1" ] && echo OFF || echo ON)
        -DJPEGXL_BUNDLE_LIBPNG=OFF
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
        -DJPEGXL_FORCE_SYSTEM_BROTLI=ON
        -DJPEGXL_FORCE_SYSTEM_LCMS2=ON
        -DJPEGXL_FORCE_SYSTEM_HWY=OFF
        # -DJPEGXL_ENABLE_LTO=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DBUILD_TESTING=OFF
    )

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DJXL_STATIC_DEFINE"

    if [[ $TARGET == linux* ]]; then
        # our glibc is too old(<2.25), and their detection fails for some reason
        export CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}"
        export CXXFLAGS="$CXXFLAGS ${USELTO}${USELTO_C} -DVQSORT_GETRANDOM=0 -DVQSORT_SECURE_SEED=0"
        export LDFLAGS="$LDFLAGS ${USELTO}"
    elif [[ $TARGET == win32 || $TARGET == win64 ]]; then
        # Fix AVX2 related crash due to unaligned stack memory
        export CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags -Wa,-muse-unaligned-vector-move -DHWY_COMPILE_ALL_ATTRIBUTES"
        export CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags -Wa,-muse-unaligned-vector-move -DHWY_COMPILE_ALL_ATTRIBUTES"
        export LDFLAGS="$LDFLAGS ${USELTO}"
    fi

    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # donor-file for aom
    mkdir -p "$FFBUILD_PREFIX/include/jxl"
    curl -fsSL "https://raw.githubusercontent.com/libjxl/libjxl/26494266bae545dc2084746a1fb22e805e119e85/lib/include/jxl/butteraugli.h" \
        -o "$FFBUILD_PREFIX/include/jxl/butteraugli.h"
    if [ ! -s "$FFBUILD_PREFIX/include/jxl/butteraugli.h" ]; then
        log_error "Failed to download butteraugli.h"
        return 1
    fi

    sed -i "s/^Requires.private: /Requires.private: lcms2 libhwy libjxl_cms /" "$PC_DIR/libjxl_cms.pc"
    sed -i 's/Libs:/Libs: -lhwy/' "$PC_DIR/libjxl.pc"
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
