#!/bin/bash

SCRIPT_REPO="https://github.com/Fraunhofer-IIS/mpeghdec"
SCRIPT_COMMIT="5f8e051c0fe249deb3d97c41bed22e92817e8378"

ffbuild_enabled() {
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
