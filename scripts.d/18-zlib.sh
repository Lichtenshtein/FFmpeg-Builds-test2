#!/bin/bash

SCRIPT_REPO="https://github.com/zlib-ng/zlib-ng.git"
SCRIPT_COMMIT="d225a913909176588060c2d5eb1d58bacd11c8c8"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    # Уходим в корень сборки этапа, чтобы сбросить любые cd из предыдущих скриптов
    cd "/build/$STAGENAME"

    # Сброс инструментов для чистоты CMake
    # unset CC CXX LD AR AS NM RANLIB
    
    mkdir -p build_zlib
    cd build_zlib

    myconf=(
        -G Ninja
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=OFF
        -DZLIB_COMPAT=ON
        -DBUILD_TESTING=OFF
        -DWITH_NEW_STRATEGIES=ON
        -DWITH_CRC32_CHORBA=ON
        -DWITH_NATIVE_INSTRUCTIONS=OFF
        -DWITH_RUNTIME_CPU_DETECTION=ON
        -DWITH_OPTIM=ON
        -DWITH_SSE2=ON
        -DWITH_SSSE3=ON
        -DWITH_SSE41=ON
        -DWITH_SSE42=ON
        -DWITH_PCLMULQDQ=ON
        -DWITH_AVX2=ON
        -DWITH_AVX512=$([ "${USE_AVX512}" == "1" ] && echo ON || echo OFF )
        -DWITH_AVX512VNNI=OFF
        -DWITH_VPCLMULQDQ=OFF
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON )

    CFLAGS="$CFLAGS $CPPFLAGS -DZLIB_STATIC" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS -DZLIB_STATIC" \
    LDFLAGS="$LDFLAGS" \
    cmake "${myconf[@]}" .. || return 1

    # Check for successful generation
    if [[ ! -f "build.ninja" ]]; then
        log_error "ERROR: CMake failed to generate build.ninja"
        return 1
    fi

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    [[ -f "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/libzlibstatic.a" ]] && mv "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/libzlibstatic.a" "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/libz.a"

    for pc in "$PC_DIR"/*zlib*.pc; do
        [[ -e "$pc" ]] || continue
        sed -i '/^Cflags:/ s/$/ -DZLIB_STATIC/' "$pc"
    done

}

ffbuild_cppflags() {
    echo "-DZLIB_STATIC"
}

ffbuild_configure() {
    echo --enable-zlib
}
