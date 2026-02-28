#!/bin/bash

SCRIPT_REPO="https://github.com/zdenop/jbigkit.git"
SCRIPT_COMMIT="4690140176ddbc3943d2b794d4b31993d7a509e1"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    mkdir build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=OFF
        -DBUILD_PROGRAMS=OFF
        -DBUILD_TOOLS=OFF
        -DCMAKE_WARN_DEPRECATED=OFF
    )

    cmake "${myconf[@]}" ..
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"
}
