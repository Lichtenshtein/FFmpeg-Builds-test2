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

    CFLAGS="$CFLAGS $CPPFLAGS -pthread -I/opt/ffbuild/include/libvmaf" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS -pthread -I/opt/ffbuild/include/libvmaf" \
    LDFLAGS="$LDFLAGS" \
    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DBUILD_SHARED_LIBS=OFF \
        -DENABLE_EXAMPLES=NO \
        -DENABLE_TESTS=NO \
        -DENABLE_TOOLS=NO \
        -DCONFIG_TUNE_VMAF=1 .. || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    echo "Requires.private: libvmaf" >> "$PC_DIR/aom.pc"

}

ffbuild_configure() {
    echo --enable-libaom
}

ffbuild_unconfigure() {
    echo --disable-libaom
}
