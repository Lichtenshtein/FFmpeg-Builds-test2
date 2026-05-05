#!/bin/bash

SCRIPT_REPO="https://github.com/mm2/Little-CMS.git"
SCRIPT_COMMIT="a4c87ebbfdd3b1c493e5ecca5f36d991b137fc95"

ffbuild_depends() {
    echo libjpeg-turbo
    echo libtiff
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir build && cd build

    local DEP_LIBS="-ltiffxx -ltiff -lturbojpeg -ljpeg -ljbig -lzstd -llzma -lz"
    local WIN_LIBS="$LIBS"

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_POLICY_DEFAULT_CMP0069=NEW
        # -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -DLCMS2_BUILD_SHARED=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DLCMS2_BUILD_STATIC=$([ "${PREFER_SHARED}" == "1" ] && echo OFF || echo ON)
        -DLCMS2_BUILD_TOOLS=OFF
        -DLCMS2_BUILD_TESTS=OFF
        -DLCMS2_BUILD_JPGICC=OFF # build jpgicc tool (requires JPEG)
        -DLCMS2_BUILD_TIFICC=OFF # build tificc tool (requires TIFF, optionally ZLIB)
        -DLCMS2_BUILD_TIFFDIFF=OFF # build tiffdiff tool (requires TIFF)
        -DLCMS2_WITH_JPEG=OFF
        -DLCMS2_WITH_TIFF=OFF
        -DLCMS2_WITH_ZLIB=OFF
        -DLCMS2_WITH_THREADS=ON # enable thread support where applicable
        -DLCMS2_WITH_FASTFLOAT=ON
        -DLCMS2_WITH_THREADED_PLUGIN=ON
    )

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja -j$(nproc) $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    local PC_FILE="$PC_DIR/lcms2.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i '/^Cflags:/ s/[[:space:]]*-pthread//g' "$PC_FILE"
    fi
}

ffbuild_configure() {
    echo --enable-lcms2
}

ffbuild_unconfigure() {
    echo --disable-lcms2
}
