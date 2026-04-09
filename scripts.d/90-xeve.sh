#!/bin/bash

SCRIPT_REPO="https://github.com/mpeg5/xeve.git"
SCRIPT_COMMIT="bc45faa2e8d22bf33b0d15c025662f2a8de61fbc"

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
        echo v0.5.1 >> version.txt
    fi
    
    mkdir -p build && cd build

    local myconf=(
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
    )

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    mv "$FFBUILD_DESTPREFIX"/lib/xeve/libxeve.a "$FFBUILD_DESTPREFIX"/lib
    
    if [[ $TARGET == win* ]]; then
        rm "$FFBUILD_DESTPREFIX"/bin/libxeve.dll
        rm "$FFBUILD_DESTPREFIX"/lib/libxeve.dll.a
    elif [[ $TARGET == linux* ]]; then
        rm "$FFBUILD_DESTPREFIX"/lib/libxeve.so*
    fi

}

ffbuild_configure() {
    echo --enable-libxeve
}

ffbuild_unconfigure() {
    echo --disable-libxeve
}