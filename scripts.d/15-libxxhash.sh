#!/bin/bash

SCRIPT_REPO="https://github.com/Cyan4973/xxHash.git"
SCRIPT_COMMIT="e573d4d2aaeaba0f3e5a0a9a54144a1f2b4b56e7"


ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    cd build/cmake

    mkdir -p build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DXXHASH_BUILD_XXHSUM=OFF
        -DXXHASH_DISPATCH=ON
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
    )

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1
    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    mkdir -p "$PC_DIR"
    if [[ ! -f "$PC_DIR/libxxhash.pc" ]]; then
        cat <<EOF > "$PC_DIR/libxxhash.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: xxhash
Description: Extremely fast hash algorithm
Version: $VER_FULL
Libs: -L\${libdir} -lxxhash
Cflags: -I\${includedir}
EOF
    fi
}
