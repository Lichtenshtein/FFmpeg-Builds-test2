#!/bin/bash

SCRIPT_REPO="https://github.com/alanxz/rabbitmq-c.git"
SCRIPT_COMMIT="8b7471eab8d09536b3c104dbb30a65699cf48104"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    mkdir build && cd build

    local mycmake=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_BUILD_TYPE=Release
        -DBUILD_SHARED_LIBS=OFF
        -DBUILD_STATIC_LIBS=ON
        -DBUILD_EXAMPLES=OFF
        -DBUILD_TESTS=OFF
        -DBUILD_TOOLS=OFF
        -DENABLE_SSL_SUPPORT=ON
    )

    cmake "${mycmake[@]}" ..
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-librabbitmq
}

ffbuild_unconfigure() {
    echo --disable-librabbitmq
}
