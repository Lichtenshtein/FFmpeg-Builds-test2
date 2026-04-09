#!/bin/bash

SCRIPT_REPO="https://github.com/cmusphinx/pocketsphinx.git"
SCRIPT_COMMIT="0d7b0ca61652d98c12de0105a1fb17ec03fe9c05"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build && cd build

    if [[ "$CC" != *clang* ]]; then
        export CFLAGS="$CFLAGS $CPPFLAGS -fpermissive -Wno-error=uninitialized -Wno-error=maybe-uninitialized"
        export CXXFLAGS="$CXXFLAGS $CPPFLAGS -fpermissive -Wno-error=uninitialized -Wno-error=maybe-uninitialized"
        export LDFLAGS="$LDFLAGS"
    else
        export CFLAGS="$CFLAGS $CPPFLAGS"
        export CXXFLAGS="$CXXFLAGS $CPPFLAGS"
        export LDFLAGS="$LDFLAGS"
    fi

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
    )

    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    cp -f ../include/pocketsphinx.h "$FFBUILD_DESTPREFIX"/include/pocketsphinx/
    rm -f "$FFBUILD_DESTPREFIX"/bin/pocketsphin*
}

ffbuild_configure() {
    echo --enable-pocketsphinx
}

ffbuild_unconfigure() {
    echo --disable-pocketsphinx
}