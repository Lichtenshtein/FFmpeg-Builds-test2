#!/bin/bash

SCRIPT_REPO="https://github.com/OpenVisualCloud/SVT-VP9.git"
SCRIPT_COMMIT="7917f95c3849768ab569ccc4a5adecb8854b65f6"

ffbuild_enabled() {
    [[ $TARGET == win32 ]] && return 1
    [[ $TARGET == *arm64 ]] && return 1
    return 0
}

fixarm64=()

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    apply_patches

    mkdir build1 && cd build1

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DBUILD_SHARED_LIBS=OFF .. || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    get_deps_list
}

ffbuild_configure() {
    echo --enable-libsvtvp9
}

ffbuild_unconfigure() {
    echo --disable-libsvtvp9
}
