#!/bin/bash

SCRIPT_REPO="https://github.com/kcat/openal-soft.git"
SCRIPT_COMMIT="266538011d2fc8ee875abed0be43a537d0e59743"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    mkdir cm_build && cd cm_build

    CFLAGS="$CFLAGS $CPPFLAGS -include stdlib.h" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS -include cstdlib" \
    LDFLAGS="$LDFLAGS" \
    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DLIBTYPE=STATIC \
        -DALSOFT_UTILS=OFF \
        -DALSOFT_EXAMPLES=OFF .. || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    echo "Libs.private: -lstdc++" >> "$PC_DIR/openal.pc"

    if [[ $TARGET == win* ]]; then
        echo "Libs.private: -lole32 -luuid" >> "$PC_DIR/openal.pc"
    fi

}

ffbuild_configure() {
    echo --enable-openal
}

ffbuild_unconfigure() {
    echo --disable-openal
}
