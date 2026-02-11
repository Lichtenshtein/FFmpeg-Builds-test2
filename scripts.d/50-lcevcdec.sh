#!/bin/bash

SCRIPT_REPO="https://github.com/MartinEesmaa/LCEVCdec.git"
SCRIPT_COMMIT="5ee432d5662268ac238791a93f2c829bcf75b6e3"

ffbuild_enabled() {
    [[ $TARGET == winarm* ]] && return -1
    (( $(ffbuild_ffver) > 800 )) || return -1
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
}

ffbuild_dockerbuild() {

    mkdir build && cd build

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
        -DBUILD_SHARED_LIBS=OFF \
        -DVN_SDK_FFMPEG_LIBS_PACKAGE="" \
        -DVN_SDK_{JSON_CONFIG,EXECUTABLES,UNIT_TESTS,SAMPLE_SOURCE}=OFF .. -G Ninja

    ninja -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja install

    echo "prefix=$FFBUILD_DESTPREFIX" > lcevc_dec.pc
    echo "libdir=\${exec_prefix}/lib" >> lcevc_dec.pc
    echo "includedir=\${prefix}/include" >> lcevc_dec.pc
    echo >> lcevc_dec.pc
    echo "Name: lcevc_dec" >> lcevc_dec.pc
    echo "Description: LCEVC Decoder SDK" >> lcevc_dec.pc
    echo "Version: 3.3.7" >> lcevc_dec.pc
    echo "Libs: -L\${libdir} -llcevc_dec_api -lstdc++ -lm" >> lcevc_dec.pc
    echo "Cflags: -I\${includedir} -DVNEnablePublicAPIExport" >> lcevc_dec.pc

    mv lcevc_dec.pc "$FFBUILD_DESTPREFIX"/lib/pkgconfig/lcevc_dec.pc
}

ffbuild_configure() {
    echo --enable-liblcevc_dec
}

ffbuild_unconfigure() {
    (( $(ffbuild_ffver) > 701 )) || return 0
    echo --disable-liblcevc_dec
}
