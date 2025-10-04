#!/bin/bash

SCRIPT_REPO="https://github.com/MartinEesmaa/mpeghdec"
SCRIPT_COMMIT="639b7a9ff12887adc0bd6b086691f2dc4e1c95b2"

ffbuild_enabled() {
    [[ $TARGET == win32 ]] && return -1
    [[ $TARGET == winarm64 ]] && return -1
    [[ $VARIANT == nonfree* ]] || return -1
    return 0
}

ffbuild_dockerbuild() {
    mkdir build && cd build

    local winfix=()
    if [[ $TARGET == win* ]]; then
        winfix+=( -DCMAKE_CXX_FLAGS="$CXXFLAGS -D_MSC_VER" )
    fi

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF -Dmpeghdec_BUILD_{BINARIES,UIMANAGER}=OFF "${winfix[@]}" ..

    make -j$(nproc)
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-libmpeghdec
}

ffbuild_unconfigure() {
    (( $(ffbuild_ffver) > 800 )) || return 0
    echo --disable-libmpeghdec
}

ffbuild_cflags() {
    echo -DMPEGHDEC_STATIC
}
