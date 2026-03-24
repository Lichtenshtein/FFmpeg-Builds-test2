#!/bin/bash

SCRIPT_REPO="https://github.com/Haivision/srt.git"
SCRIPT_COMMIT="2220de504027b0fc45012b459365505834300e31"

ffbuild_depends() {
    echo base
    echo openssl
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

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DENABLE_SHARED=OFF \
        -DENABLE_STATIC=ON \
        -DENABLE_CXX_DEPS=ON \
        -DUSE_STATIC_LIBSTDCXX=ON \
        -DENABLE_ENCRYPTION=ON \
        -DENABLE_APPS=OFF .. || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    echo "Libs.private: -lstdc++" >> "$PC_DIR/srt.pc"

}

ffbuild_configure() {
    echo --enable-libsrt
}

ffbuild_unconfigure() {
    echo --disable-libsrt
}
