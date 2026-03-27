#!/bin/bash

SCRIPT_REPO="https://github.com/libjpeg-turbo/libjpeg-turbo.git"
SCRIPT_COMMIT="4d293d9400281045e062b6e4eb8e1ccfc89d91f8"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    mkdir build && cd build

    local myconf=(
        "Unix Makefiles"
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DENABLE_SHARED=OFF
        -DENABLE_STATIC=ON
        -DWITH_JPEG8=ON
        -DWITH_SIMD=ON
        -DWITH_TOOLS=OFF
        -DWITH_TESTS=OFF
        -DWITH_TURBOJPEG=ON
    )

    [[ "$USE_LTO" == "1" ]] && myconf+=( -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON )

    CFLAGS="$CFLAGS $CPPFLAGS -DLIBJPEG_STATIC" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS -DLIBJPEG_STATIC" \
    LDFLAGS="$LDFLAGS" \
    cmake -G "${myconf[@]}" .. || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    for pc in "$PC_DIR"/*jpeg*.pc; do
        [[ -e "$pc" ]] || continue
        sed -i '/^Cflags:/ s/$/ -DLIBJPEG_STATIC/' "$pc"
    done

}

ffbuild_cppflags() {
    echo "-DLIBJPEG_STATIC"
}
