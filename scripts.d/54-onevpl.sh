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

    local myconf=(
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_INSTALL_BINDIR="$FFBUILD_PREFIX"/bin
        -DCMAKE_INSTALL_LIBDIR="$FFBUILD_PREFIX"/lib
        -DBUILD_EXAMPLES=OFF
        -DBUILD_EXPERIMENTAL=ON
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DBUILD_TESTS=OFF
        -DINSTALL_EXAMPLES=OFF
        -DINSTALL_LIB=ON
        )

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    rm -rf "$FFBUILD_DESTPREFIX"/{etc,share}

    sed -i '/^Libs.private:/ s/$/ -lstdc++/' "$PC_DIR/vpl.pc"
}

ffbuild_configure() {
    echo --enable-libvpl
}

ffbuild_unconfigure() {
    echo --disable-libvpl
}
