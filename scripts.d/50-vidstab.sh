#!/bin/bash

SCRIPT_REPO="https://github.com/georgmartius/vid.stab.git"
SCRIPT_COMMIT="92bc0b0f369f2a88aaacf25eac3a10f8415308fc"

ffbuild_enabled() {
    [[ $VARIANT == lgpl* ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
}

ffbuild_dockerbuild() {
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

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" "${mycmake[@]}" ..
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    if [[ $TARGET == linux* ]]; then
        echo "Libs.private: -ldl" >> "$FFBUILD_DESTPREFIX"/lib/pkgconfig/vidstab.pc
    fi
}

ffbuild_configure() {
    echo --enable-libvidstab
}

ffbuild_unconfigure() {
    echo --disable-libvidstab
}
