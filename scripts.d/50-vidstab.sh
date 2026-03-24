#!/bin/bash

SCRIPT_REPO="https://github.com/georgmartius/vid.stab.git"
SCRIPT_COMMIT="92bc0b0f369f2a88aaacf25eac3a10f8415308fc"

ffbuild_enabled() {
    [[ $VARIANT == lgpl* ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    mkdir build && cd build

    local mycmake=(
        -DBUILD_SHARED_LIBS=OFF
        -DUSE_OMP=ON
    )

    if [[ $TARGET == *arm64 ]]; then
        mycmake+=(
            -DSSE2_FOUND=FALSE
        )
    fi

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" "${mycmake[@]}" .. || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    if [[ $TARGET == linux* ]]; then
        echo "Libs.private: -ldl" >> "$PC_DIR/vidstab.pc"
    fi

}

ffbuild_configure() {
    echo --enable-libvidstab
}

ffbuild_unconfigure() {
    echo --disable-libvidstab
}
