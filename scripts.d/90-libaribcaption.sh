#!/bin/bash

SCRIPT_REPO="https://github.com/xqq/libaribcaption.git"
SCRIPT_COMMIT="27cf3cab26084d636905335d92c375ecbc3633ea"

ffbuild_depends() {
    echo base
    echo freetype
    echo fontconfig
    echo harfbuzz
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
    mkdir build
    cd build

    CFLAGS="$CFLAGS $CPPFLAGS -DHAVE_OPENSSL=1" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DARIBCC_SHARED_LIBRARY=OFF \
        -DARIBCC_BUILD_TESTS=OFF \
        -DBUILD_SHARED_LIBS=OFF \
        -DARIBCC_USE_FREETYPE=ON \
        -DARIBCC_USE_EMBEDDED_FREETYPE=OFF .. || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    echo "Libs.private: -lstdc++ -lcrypto" >> "$PC_DIR/libaribcaption.pc"

}

ffbuild_configure() {
    echo --enable-libaribcaption
}

ffbuild_unconfigure() {
    echo --disable-libaribcaption
}
