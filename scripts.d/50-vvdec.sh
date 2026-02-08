#!/bin/bash

SCRIPT_REPO="https://github.com/fraunhoferhhi/vvdec"
SCRIPT_COMMIT="9a4349460e4c61232c3e2cfabecb508616ae8c2f"

ffbuild_enabled() {
    [[ $TARGET == win32 ]] && return -1
    [[ $TARGET == winarm* ]] && return -1
    (( $(ffbuild_ffver) > 700 )) || return -1
    return 0
}

ffbuild_dockerbuild() {
    mkdir build && cd build

    local armsimd=()
    if [[ $TARGET == linuxarm64 ]]; then
        armsimd+=( -DVVDEC_ENABLE_ARM_SIMD=ON )

        if [[ "$CC" != *clang* ]]; then
            export CFLAGS="$CFLAGS -fpermissive -Wno-error=uninitialized -Wno-error=maybe-uninitialized"
            export CXXFLAGS="$CXXFLAGS -fpermissive -Wno-error=uninitialized -Wno-error=maybe-uninitialized"
        fi
    fi

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
         -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
         -DCMAKE_BUILD_TYPE=Release \
         -DCMAKE_C_FLAGS="$CFLAGS" \
         -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
         -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
         -DBUILD_SHARED_LIBS=OFF \
         -DEXTRALIBS="-lstdc++" \
         -DVVDEC_ENABLE_LINK_TIME_OPT=OFF "${armsimd[@]}" ..

    make -j$(nproc)
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-libvvdec
}

ffbuild_unconfigure() {
    (( $(ffbuild_ffver) > 700 )) || return 0
    echo --disable-libvvdec
}