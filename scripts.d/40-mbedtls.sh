#!/bin/bash

SCRIPT_REPO="https://github.com/ARMmbed/mbedtls.git"
SCRIPT_COMMIT="v3.6.5"
SCRIPT_TAGFILTER="v3.*"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-submodule-clone"
}

ffbuild_dockerbuild() {
    set -e
    if [[ $TARGET == win32 ]]; then
        python3 scripts/config.py unset MBEDTLS_AESNI_C
    fi

    mkdir build && cd build

    CFLAGS="$CFLAGS $CPPFLAGS -Wno-error=array-bounds" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS -Wno-error=array-bounds" \
    LDFLAGS="$LDFLAGS" \
    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF ) \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DENABLE_PROGRAMS=OFF \
        -DENABLE_TESTING=OFF \
        -DGEN_FILES=ON \
        -DUSE_STATIC_MBEDTLS_LIBRARY=ON \
        -DUSE_SHARED_MBEDTLS_LIBRARY=OFF \
        -DINSTALL_MBEDTLS_HEADERS=ON .. || return 1

    make -j$(nproc) || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    if [[ $TARGET == win* ]]; then
        echo "Libs.private: -lws2_32 -lbcrypt -lwinmm -lgdi32" >> "$PC_DIR/mbedcrypto.pc"
    fi

}
