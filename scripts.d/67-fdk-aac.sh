#!/bin/bash

# SCRIPT_REPO="https://github.com/mstorsjo/fdk-aac.git"
# SCRIPT_COMMIT="d8e6b1a3aa606c450241632b64b703f21ea31ce3"

SCRIPT_REPO2="https://github.com/Rancemxn/fdk-aac.git"
SCRIPT_COMMIT2="d05a2f3e7678d987bde2a2c10101c7cb91711905"

ffbuild_enabled() {
    [[ $VARIANT == nonfree* ]] || return 1
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
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DBUILD_PROGRAMS=OFF
        -DFDK_AAC_INSTALL_CMAKE_CONFIG_MODULE=ON
        -DFDK_AAC_INSTALL_PKGCONFIG_MODULE=ON # Install pkg-config .pc file
    )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    sed -i "s|^Cflags:.*|& -I\${includedir}/fdk-aac|" "$PC_DIR/fdk-aac.pc"
}

ffbuild_configure() {
    echo --enable-libfdk-aac
}

ffbuild_unconfigure() {
    echo --disable-libfdk-aac
}
