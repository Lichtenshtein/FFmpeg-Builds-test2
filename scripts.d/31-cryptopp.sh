#!/bin/bash

SCRIPT_REPO="https://github.com/abdes/cryptopp-cmake.git"
SCRIPT_COMMIT="866aceb8b13b6427a3c4541288ff412ad54f11ea"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build && cd build

    local myconf=(
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCRYPTOPP_BUILD_SHARED=OFF
        -DCRYPTOPP_BUILD_TESTING=OFF
        -DCRYPTOPP_BUILD_DOCUMENTATION=OFF
        -DCRYPTOPP_USE_OPENMP="$([ "$USE_OPENMP" == "1" ] && echo ON || echo OFF)"
        -DCRYPTOPP_USE_INTERMEDIATE_OBJECTS_TARGET=ON
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    )

    CFLAGS="$CFLAGS" \
    CPPFLAGS="$CPPFLAGS $static_flags" \
    CXXFLAGS="$CXXFLAGS $static_flags" \
    LDFLAGS="$LDFLAGS" \
    LIBS="$LIBS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # Исправляем .pc файл, если cryptopp-cmake его криво генерирует для статики
    # local PC_FILE="$PC_DIR/cryptopp.pc"
    # if [[ -f "$PC_FILE" ]]; then
        # sed -i 's/-lcryptopp/-lcryptopp/g' "$PC_FILE"
    # fi
}
