#!/bin/bash

SCRIPT_REPO="https://github.com/cynagenautes/AudioToolboxWrapper.git"
SCRIPT_COMMIT="191aa1bf840e093cad48a5d34c961086641bacbd"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    sed -i 's/cmake_minimum_required (VERSION 3.0)/cmake_minimum_required (VERSION 3.5)/' CMakeLists.txt

    mkdir build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo 1 || echo 0)
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/AudioToolboxWrapper.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: AudioToolboxWrapper
Description: AudioToolbox wrapper for MinGW
Version: 1.0
Libs: -L\${libdir} -lAudioToolboxWrapper
Cflags: -I\${includedir} -I\${includedir}/AudioToolbox
EOF
}

ffbuild_configure() {
    echo --enable-audiotoolbox
}

ffbuild_unconfigure() {
    echo --disable-audiotoolbox
}

ffbuild_libs() {
    echo -lAudioToolboxWrapper
}
