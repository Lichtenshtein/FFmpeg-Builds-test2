#!/bin/bash

SCRIPT_REPO="https://github.com/google/brotli.git"
SCRIPT_COMMIT="5fa73e23bee34f84148719576a7a434f0fc43dc8"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    mkdir build && cd build

    CFLAGS="$CFLAGS $CPPFLAGS -DBROTLI_STATIC" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS -DBROTLI_STATIC" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF ) \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DBUILD_SHARED_LIBS=OFF .. || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    for pc in "$PC_DIR"/*brotli*.pc; do
        [[ -e "$pc" ]] || continue
        sed -i '/^Cflags:/ s/$/ -DBROTLI_STATIC/' "$pc"
    done

}

ffbuild_cppflags() {
    echo "-DBROTLI_STATIC"
}
