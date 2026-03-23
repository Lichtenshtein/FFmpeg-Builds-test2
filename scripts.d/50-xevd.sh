#!/bin/bash

SCRIPT_REPO="https://github.com/mpeg5/xevd.git"
SCRIPT_COMMIT="4087f635624cf4ee6ebe3f9ea165ff939b32117f"

ffbuild_enabled() {
    [[ $TARGET == *arm64 ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    if [ ! -f "version.txt" ]; then
        echo v0.5.0 >> version.txt
    fi
    
    mkdir build && cd build

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF ) \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" .. || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    mv "$FFBUILD_DESTPREFIX"/lib/xevd/libxevd.a "$FFBUILD_DESTPREFIX"/lib
    
    if [[ $TARGET == win* ]]; then
        rm "$FFBUILD_DESTPREFIX"/bin/libxevd.dll
        rm "$FFBUILD_DESTPREFIX"/lib/libxevd.dll.a
    elif [[ $TARGET == linux* ]]; then
        rm "$FFBUILD_DESTPREFIX"/lib/libxevd.so*
    fi

}

ffbuild_configure() {
    echo --enable-libxevd
}

ffbuild_unconfigure() {
    echo --disable-libxevd
}