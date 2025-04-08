#!/bin/bash

SCRIPT_REPO="https://github.com/cmusphinx/pocketsphinx.git"
SCRIPT_COMMIT="0d7b0ca61652d98c12de0105a1fb17ec03fe9c05"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {

    mkdir build && cd build

    if [[ "$CC" != *clang* ]]; then
        export CFLAGS="$CFLAGS -fpermissive -Wno-error=uninitialized -Wno-error=maybe-uninitialized"
        export CXXFLAGS="$CXXFLAGS -fpermissive -Wno-error=uninitialized -Wno-error=maybe-uninitialized"
    fi

    cmake -G Ninja -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF ..

    ninja -j$(nproc)
    ninja install

    cp -f ../include/pocketsphinx.h "$FFBUILD_PREFIX"/include/pocketsphinx/
    rm -f "$FFBUILD_PREFIX"/bin/pocketsphin*
}

ffbuild_configure() {
    echo --enable-pocketsphinx
}

ffbuild_unconfigure() {
    echo --disable-pocketsphinx
}