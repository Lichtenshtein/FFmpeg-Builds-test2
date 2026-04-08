#!/bin/bash

SCRIPT_REPO="https://github.com/acoustid/chromaprint.git"
SCRIPT_COMMIT="6b13ce3a81ae931e7477c4856a86bece99157cd8"

ffbuild_depends() {
    echo base
    echo fftw3
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DBUILD_TOOLS=OFF
        -DBUILD_TESTS=OFF
        -DFFT_LIB=fftw3
    )

    local static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DCHROMAPRINT_NODLL"

    CFLAGS="$CFLAGS $CPPFLAGS $static_flags" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS $static_flags" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    echo "Libs.private: -lfftw3 -lstdc++" >> "$PC_DIR/libchromaprint.pc"
    echo "Cflags.private: $static_flags" >> "$PC_DIR/libchromaprint.pc"
}

ffbuild_configure() {
    echo --enable-chromaprint
}

ffbuild_unconfigure() {
    echo --disable-chromaprint
}
