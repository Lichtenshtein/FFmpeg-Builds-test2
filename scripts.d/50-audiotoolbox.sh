#!/bin/bash

SCRIPT_REPO="https://github.com/cynagenautes/AudioToolboxWrapper.git"
SCRIPT_COMMIT="191aa1bf840e093cad48a5d34c961086641bacbd"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
}

ffbuild_dockerbuild() {
    mkdir build && cd build

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" .. -G Ninja
    ninja -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja install

    rm "$FFBUILD_DESTPREFIX"/bin/atw_ldwrapper
}

ffbuild_configure() {
    echo --enable-audiotoolbox --disable-outdev=audiotoolbox
}

ffbuild_unconfigure() {
    echo --disable-audiotoolbox
}

ffbuild_libs() {
    echo -lAudioToolboxWrapper
}
