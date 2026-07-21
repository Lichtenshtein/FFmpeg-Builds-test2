#!/bin/bash

SCRIPT_REPO="https://github.com/cmusphinx/pocketsphinx.git"
SCRIPT_COMMIT="511126b492dcb267cf30d49d631946d7b61a9530"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "rm -rf test"
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build && cd build

    if [[ "${CC}" != *clang* ]]; then
        export CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -fpermissive -Wno-error=uninitialized -Wno-error=maybe-uninitialized"
        export CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} -fpermissive -Wno-error=uninitialized -Wno-error=maybe-uninitialized"
        export LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}"
    else
        export CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}"
        export CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}"
        export LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}"
    fi

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DFIXED_POINT=OFF # Build using fixed-point math
        -DPS_THREAD_LOCAL_RNG=ON # Use thread-local storage for random number generator
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
    )

    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    cp -f${OP_V} ../include/pocketsphinx.h "$INSTALL_ROOT"/include/pocketsphinx/
    rm -f "$INSTALL_ROOT"/bin/pocketsphin*
}

ffbuild_configure() {
    echo --enable-pocketsphinx
}

ffbuild_unconfigure() {
    echo --disable-pocketsphinx
}