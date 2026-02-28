#!/bin/bash

SCRIPT_REPO="https://gitlab.com/libssh/libssh-mirror.git"
SCRIPT_COMMIT="34db488e4db8c66175c3ec4e31e724173b5263a3"

ffbuild_depends() {
    echo base
    echo zlib
    echo openssl
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    mkdir build && cd build

    export CFLAGS="$CFLAGS -Dmd5=libssh_md5 -DLIBSSH_STATIC"

    cmake -GNinja \
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DBUILD_SHARED_LIBS=OFF \
        -DWITH_EXAMPLES=OFF \
        -DWITH_SERVER=OFF \
        -DWITH_SFTP=ON \
        -DWITH_ZLIB=ON ..

    ninja -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja install

    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/libssh.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i '/^Cflags:/ s/$/ -DLIBSSH_STATIC/' "$PC_FILE"
        echo "Libs.private: -lws2_32 -liphlpapi -lpthread" >> "$PC_FILE"
    fi

ffbuild_cflags() {
    echo "-DLIBSSH_STATIC"
}

ffbuild_configure() {
    echo --enable-libssh
}

ffbuild_unconfigure() {
    echo --disable-libssh
}
