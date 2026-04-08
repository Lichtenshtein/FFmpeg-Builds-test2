#!/bin/bash

SCRIPT_REPO="https://aomedia.googlesource.com/aom"
SCRIPT_COMMIT="0dfe179f80da866a291728590fd1bbc3b5e6fe0a"

ffbuild_depends() {
    echo base
    echo vmaf
}

ffbuild_enabled() {
    return 1
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir cmbuild && cd cmbuild

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DENABLE_EXAMPLES=NO
        -DENABLE_TESTS=NO
        -DENABLE_TOOLS=NO
        -DCONFIG_TUNE_VMAF=1
    )

    CFLAGS="$CFLAGS $CPPFLAGS -pthread -I/opt/ffbuild/include/libvmaf" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS -pthread -I/opt/ffbuild/include/libvmaf" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    echo "Requires.private: libvmaf" >> "$PC_DIR/aom.pc"
}

ffbuild_configure() {
    echo --enable-libaom
}

ffbuild_unconfigure() {
    echo --disable-libaom
}
