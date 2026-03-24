#!/bin/bash

SCRIPT_REPO="https://github.com/intel/libvpl.git"
SCRIPT_COMMIT="778a66d6c6537f08eabb91955dbbf1bce3812894"

ffbuild_enabled() {
    [[ $TARGET == *arm64 ]] && return 1
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
    cmake -GNinja \
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DCMAKE_INSTALL_BINDIR="$FFBUILD_PREFIX"/bin \
        -DCMAKE_INSTALL_LIBDIR="$FFBUILD_PREFIX"/lib \
        -DBUILD_DISPATCHER=ON \
        -DBUILD_DEV=ON \
        -DBUILD_PREVIEW=OFF \
        -DBUILD_TOOLS=OFF \
        -DBUILD_TOOLS_ONEVPL_EXPERIMENTAL=OFF \
        -DINSTALL_EXAMPLE_CODE=OFF \
        -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_TESTS=OFF .. || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    rm -rf "$FFBUILD_DESTPREFIX"/{etc,share}

    echo "Libs.private: -lstdc++" >> "$PC_DIR/vpl.pc"

}

ffbuild_configure() {
    echo --enable-libvpl
}

ffbuild_unconfigure() {
    echo --disable-libvpl
}
