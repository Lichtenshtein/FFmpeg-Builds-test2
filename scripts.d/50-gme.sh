#!/bin/bash

#SCRIPT_REPO="https://github.com/libgme/game-music-emu.git"
#SCRIPT_COMMIT="da7606bce80794cf1b78865666761b1ba61d82da"

SCRIPT_REPO="https://github.com/myQwil/game-music-emu.git"
SCRIPT_COMMIT="c6b70bf66fc681f9450eec64fc4d6e19d753662a"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
}

ffbuild_dockerbuild() {
    mkdir build && cd build

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DCMAKE_DISABLE_FIND_PACKAGE_SDL2=1 \
        -DBUILD_SHARED_LIBS=OFF \
        -DENABLE_UBSAN=OFF ..
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-libgme
}

ffbuild_unconfigure() {
    echo --disable-libgme
}
