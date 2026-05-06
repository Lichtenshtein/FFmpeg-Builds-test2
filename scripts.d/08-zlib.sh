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
    
    mkdir -p build_zlib && cd build_zlib

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
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
        -DWITH_AVX512VNNI=$([ "${USE_AVX512}" == "1" ] && echo ON || echo OFF )
        -DWITH_VPCLMULQDQ=OFF
    )

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DZLIB_STATIC"

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    # Check for successful generation
    if [[ ! -f "build.ninja" ]]; then
        log_error "CMake failed to generate build.ninja"
        return 1
    fi

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    [[ -f "$INSTALL_ROOT/lib/libzlibstatic.a" ]] && mv "$INSTALL_ROOT/lib/libzlibstatic.a" "$INSTALL_ROOT/lib/libz.a"

    for pc in "$PC_DIR"/*zlib*.pc; do
        [[ -e "$pc" ]] || continue
        if [[ -n "$static_flags" ]]; then
            if ! grep -qF -- "$static_flags" "$pc"; then
                sed -i "/^Cflags:/ s/$/ $static_flags/" "$pc"
            fi
        fi
    done
}

ffbuild_cppflags() {
    echo "$static_flags"
}

ffbuild_configure() {
    echo --enable-zlib
}
