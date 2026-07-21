#!/bin/bash

SCRIPT_REPO="https://github.com/lensfun/lensfun.git"
SCRIPT_COMMIT="698a39eea69be00f4f25b6da6c1ad34b1f162b50"

ffbuild_depends() {
    echo base
    echo glib2
    echo libpng
    echo libxml2
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "rm -rf sourceforge-archive docs"
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p build && cd build

    # need to pass TWO paths to Glib includes
    local GLIB_INCLUDES="-I$FFBUILD_PREFIX/include/glib-2.0 -I$FFBUILD_PREFIX/lib/glib-2.0/include"

    local myconf=(
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DBUILD_STATIC=$([ "${PREFER_SHARED}" == "1" ] && echo OFF || echo ON)
        -DBUILD_TESTS=OFF
        -DBUILD_LENSTOOL=OFF
        -DBUILD_DOC=OFF
        -DBUILD_FOR_SSE=ON
        -DBUILD_FOR_SSE2=ON
        -DINSTALL_HELPER_SCRIPTS=ON # OFF
        # Forcefully disabling Python
        -DINSTALL_PYTHON_MODULE=OFF # OFF; Install Python module for the helper scripts
        # -DPYTHON_EXECUTABLE=OFF
        # Specifying paths for the CMake Glib search module
        -DGLIB2_LIBRARIES="$FFBUILD_PREFIX/lib/libglib-2.0.${lib_ext}"
    )

    CFLAGS="$CFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $GLIB_INCLUDES" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS ${USELTO}${USELTO_C} $GLIB_INCLUDES" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local PC_FILE="$PC_DIR/lensfun.pc"
    if [[ -f "$PC_FILE" ]]; then
        log_info "Patching lensfun.pc for static MinGW build..."
        if ! grep -q "Requires:" "$PC_FILE"; then
            sed -i '/^Requires:/ s/$/ glib-2.0/' "$PC_FILE"
        fi
    fi
}

ffbuild_configure() { echo --enable-liblensfun; }
ffbuild_unconfigure() { echo --disable-liblensfun; }
