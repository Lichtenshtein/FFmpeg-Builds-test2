#!/bin/bash

SCRIPT_REPO="https://github.com/freeglut/freeglut.git"
SCRIPT_COMMIT="cc5f150ad86f01baee98a791b393a6d74b0bfb80"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build && cd build

    local myconf=(
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF )
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DFREEGLUT_INSTALL_MAN_PAGES=OFF
        -DFREEGLUT_BUILD_DEMOS=OFF
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DFREEGLUT_BUILD_STATIC_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo OFF || echo ON)
        -DFREEGLUT_BUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DFREEGLUT_COCOA=OFF
        -DFREEGLUT_WAYLAND=OFF # Use Wayland not X11
        -DFREEGLUT_REPLACE_GLUT=ON # built as -lglut if ON; else -lfreeglut
        -DFREEGLUT_GLES=OFF
        -DINSTALL_PDB=OFF # install .pdb files
        -DFREEGLUT_PRINT_WARNINGS=OFF
        -DFREEGLUT_PRINT_ERRORS=OFF
    )

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DFREEGLUT_STATIC"

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $static_flags" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    LIBS="$LIBS $ADDITIONAL_LIBS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1
}
