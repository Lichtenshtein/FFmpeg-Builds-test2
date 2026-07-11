#!/bin/bash

# SCRIPT_REPO="https://github.com/Brainiarc7/SVT-HEVC.git"
# SCRIPT_COMMIT="ee950558a2e3d0f0e3d78365b61a8f6020bd24de"

SCRIPT_REPO="https://github.com/possible947/SVT-HEVC.git"
SCRIPT_COMMIT="bbc686f04c4de43836c166c792377e21f8e630a5"

ffbuild_enabled() {
    [[ $TARGET == win32 ]] && return 1
    [[ $TARGET == *arm64 ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p _build && cd _build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_APP=OFF
        # added by patch or from fork
        -DSVT_ENABLE_LTO=OFF # to overrite -fno-fat-lto-objects
        -DSVT_ENABLE_PORTABLE_RPATH=OFF # portable build RPATH for side-by-side binaries
        -DSVT_ENABLE_INSTALL_RPATH=OFF # RPATH to locate libraries under the install prefix
        -DSVT_ENABLE_NATIVE=OFF # Build for native performance (march=native)
    )

    if [[ "${PREFER_SHARED}" == "1" ]]; then
        myconf+=(
        -DBUILD_SHARED_LIBS=ON
        )
    else
        myconf+=(
        -DBUILD_SHARED_LIBS=OFF
        -DSVT_ENABLE_FULL_STATIC=ON # fully static executables where supported
        )
    fi

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    sed -i "s|^Cflags:.*|& -I\${includedir}/svt-hevc|" "$PC_DIR/SvtHevcEnc.pc"
}

ffbuild_configure() {
    echo --enable-libsvthevc
}

ffbuild_unconfigure() {
    echo --disable-libsvthevc
}
