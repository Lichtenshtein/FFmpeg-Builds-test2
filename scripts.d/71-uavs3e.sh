#!/bin/bash

SCRIPT_REPO="https://github.com/MartinEesmaa/uavs3e.git"
SCRIPT_COMMIT="eca828b2cf05ebb7fef2e2505e3ee2a2156ba2b1"

ffbuild_enabled() {
    [[ $TARGET == win32 ]] && return 1
    [[ $TARGET == winarm64 ]] && return 1
    [[ $TARGET == linuxarm64 ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p _build && cd _build

    local myconf=(
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCOMPILE_10BIT=1
        -DCOMPILE_FFMPEG=ON
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # Just in case to detect header files default before FFmpeg
    cp -f "$INSTALL_ROOT"/include/uavs3e/uavs3e.h "$INSTALL_ROOT"/include
    cp -f "$INSTALL_ROOT"/include/uavs3e/com_api.h "$INSTALL_ROOT"/include

    sed -i "s|^Cflags:.*|& -I${includedir}/uavs3e|" "$PC_DIR/uavs3e.pc"
}

ffbuild_configure() {
    echo --enable-libuavs3e
}

ffbuild_unconfigure() {
    echo --disable-libuavs3e
}
