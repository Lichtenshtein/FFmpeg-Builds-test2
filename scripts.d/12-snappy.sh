#!/bin/bash

SCRIPT_REPO="https://github.com/google/snappy.git"
SCRIPT_COMMIT="da459b5263676ccf0dc65a3fcf93fb876e09baac"

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
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DSNAPPY_BUILD_TESTS=OFF
        -DSNAPPY_BUILD_BENCHMARKS=OFF
        -DSNAPPY_REQUIRE_AVX=ON
        -DSNAPPY_REQUIRE_AVX2=ON
        -DSNAPPY_INSTALL=ON
    )
    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1
}

ffbuild_configure() {
    echo --enable-libsnappy
}

ffbuild_unconfigure() {
    echo --disable-libsnappy
}
