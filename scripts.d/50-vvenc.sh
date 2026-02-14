#!/bin/bash

SCRIPT_REPO="https://github.com/fraunhoferhhi/vvenc.git"
SCRIPT_COMMIT="6627583b7d2b607a7fb04b97ab29d66bdcb113cf"

ffbuild_enabled() {
    [[ $TARGET == winarm* ]] && return -1
    (( $(ffbuild_ffver) > 700 )) || return -1
    return 0
    # vvenc force-enabled avx2 and equivalent compiler options, and uses a static initializer that promptly
    # runs such instructions. Making resulting binaries malfunction on any but the very latest CPUs.
    # Until upstream fixes this behaviour, force-disable vvenc.
    # I force enabled just in case cause BtBn force disabled vvenc for avx2 enabled reason.
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
}

ffbuild_dockerbuild() {

    mkdir build && cd build

    export CFLAGS="$CFLAGS -fpermissive -Wno-error=uninitialized -Wno-error=maybe-uninitialized"
    export CXXFLAGS="$CXXFLAGS -fpermissive -Wno-error=uninitialized -Wno-error=maybe-uninitialized"

    cmake -G "Unix Makefiles" \
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
        -DBUILD_SHARED_LIBS=OFF \
        -DVVENC_LIBRARY_ONLY=ON \
        -DVVENC_ENABLE_WERROR=OFF \
        -DVVENC_ENABLE_LINK_TIME_OPT=ON \
        -DEXTRALIBS="-lstdc++ -lm" .. # -lm для математики

        # -DVVENC_ENABLE_LINK_TIME_OPT=OFF

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-libvvenc
}

ffbuild_unconfigure() {
    (( $(ffbuild_ffver) > 700 )) || return 0
    echo --disable-libvvenc
}
