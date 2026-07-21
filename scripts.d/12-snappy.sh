#!/bin/bash

SCRIPT_REPO="https://github.com/google/snappy.git"
SCRIPT_COMMIT="3ac3722e1bee4b99860a282fb779e8e72fa18163"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "rm -rf testdata"
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build && cd build

    local myconf=(
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DSNAPPY_BUILD_TESTS=OFF
        -DSNAPPY_BUILD_BENCHMARKS=OFF
        -DSNAPPY_REQUIRE_AVX=ON
        -DSNAPPY_REQUIRE_AVX2=ON
        -DSNAPPY_INSTALL=ON
    )
    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/snappy.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: Snappy
Description: A fast compressor/decompressor library
Version: ${VER_FULL}
Libs: -L\${libdir} -lsnappy
Cflags: -I\${includedir}
EOF
}

ffbuild_configure() {
    echo --enable-libsnappy
}

ffbuild_unconfigure() {
    echo --disable-libsnappy
}
