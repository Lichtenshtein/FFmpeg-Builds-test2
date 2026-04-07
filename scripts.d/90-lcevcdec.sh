#!/bin/bash

SCRIPT_REPO="https://github.com/v-novaltd/LCEVCdec.git"
SCRIPT_COMMIT="655f029d0008f00da9c976567ea159437aa86a36"

ffbuild_enabled() {
    [[ $TARGET == winarm* ]] && return 1
    return 1
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    mkdir build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DVN_SDK_GENERATE_PGO=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF) # this is NOT LTO
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DVN_SDK_FFMPEG_LIBS_PACKAGE=""
        -DVN_SDK_{JSON_CONFIG,EXECUTABLES,UNIT_TESTS,SAMPLE_SOURCE}=OFF
    )

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    echo "prefix=$FFBUILD_DESTPREFIX" > lcevc_dec.pc
    echo "libdir=\${exec_prefix}/lib" >> lcevc_dec.pc
    echo "includedir=\${prefix}/include" >> lcevc_dec.pc
    echo >> lcevc_dec.pc
    echo "Name: lcevc_dec" >> lcevc_dec.pc
    echo "Description: LCEVC Decoder SDK" >> lcevc_dec.pc
    echo "Version: 3.3.7" >> lcevc_dec.pc
    echo "Libs: -L\${libdir} -llcevc_dec_api -lstdc++ -lm" >> lcevc_dec.pc
    echo "Cflags: -I\${includedir} -DVNEnablePublicAPIExport" >> lcevc_dec.pc

    mv lcevc_dec.pc "$PC_DIR/lcevc_dec.pc"

}

ffbuild_configure() {
    echo --enable-liblcevc_dec
}

ffbuild_unconfigure() {
    echo --disable-liblcevc_dec
}
