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

    # donor-file for aom
if [[ "${PREFER_SHARED}" != "1" ]]; then
    cat << 'EOF'
mkdir -p lib/include/jxl
curl -fsSL "https://raw.githubusercontent.com/libjxl/libjxl/26494266bae545dc2084746a1fb22e805e119e85/lib/include/jxl/butteraugli.h" \
    -o "lib/include/jxl/butteraugli.h"
sed -i '1s/^/#define JXL_STATIC_DEFINE 1\n/' "lib/include/jxl/butteraugli.h"
if [[ -d ".git" ]]; then
    git add lib/include/jxl/butteraugli.h
fi
EOF
else
    cat << 'EOF'
mkdir -p lib/include/jxl
curl -fsSL "https://raw.githubusercontent.com/libjxl/libjxl/26494266bae545dc2084746a1fb22e805e119e85/lib/include/jxl/butteraugli.h" \
    -o "lib/include/jxl/butteraugli.h"
if [[ -d ".git" ]]; then
    git add lib/include/jxl/butteraugli.h
fi
EOF
fi

    # echo "git-submodule-clone"
    echo "mkdir -p testdata"
    echo "git-mini-clone \"https://github.com/google/highway.git\" \"master\" third_party/highway"
    echo "git-mini-clone \"https://github.com/webmproject/sjpeg.git\" \"main\" third_party/sjpeg"
    echo "rm -rf \
third_party/sjpeg/tests \
third_party/highway/g3doc \
third_party/highway/hwy/tests \
tools/benchmark"
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

    # Извлекаем butteraugli.h
    log_info "Copying butteraugli.h for the AOM compiler..."
    mkdir -p "${INSTALL_ROOT}/include/jxl"
    cp "../lib/include/jxl/butteraugli.h" "${INSTALL_ROOT}/include/jxl/butteraugli.h"
    if [ ! -s "${INSTALL_ROOT}/include/jxl/butteraugli.h" ]; then
        log_error "Failed to verify butteraugli.h in installation directory"
        return 1
    fi

    sed -i "s/^Requires.private: /Requires.private: lcms2 libhwy libjxl_cms /" "$PC_DIR/libjxl_cms.pc"
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
