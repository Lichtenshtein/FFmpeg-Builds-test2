#!/bin/bash

SCRIPT_REPO="https://github.com/openssl/openssl.git"
SCRIPT_COMMIT="c9a9e5b10105ad850b6e4d1122c645c67767c341"

ffbuild_depends() {
    echo base
    echo zlib
}

ffbuild_enabled() {
    [[ $VARIANT == nonfree* ]] || return 0
    return 0
}

ffbuild_dockerdl() {
    # echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
    # echo "git submodule --quiet update --init --recursive --depth=1"
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    cd "/build/$STAGENAME"
    local REAL_ROOT=$(find . -maxdepth 2 -name "Configure" -exec dirname {} \; | head -n 1)
    if [[ -n "$REAL_ROOT" ]]; then
        cd "$REAL_ROOT"
    fi

    # Фикс для QUIC
    sed -i '1i#ifndef SIO_UDP_NETRESET\n#define SIO_UDP_NETRESET _WSAIOW(IOC_VENDOR, 15)\n#endif' include/internal/sockets.h

    export CC="${CC/${FFBUILD_CROSS_PREFIX}/}"
    export CXX="${CXX/${FFBUILD_CROSS_PREFIX}/}"
    export AR="${AR/${FFBUILD_CROSS_PREFIX}/}"
    export RANLIB="${RANLIB/${FFBUILD_CROSS_PREFIX}/}"

    local myconf=(
        mingw64
        threads
        zlib
        no-shared
        no-tests
        no-apps
        no-legacy
        no-unit-test
        no-async
        enable-camellia
        enable-ec
        enable-srp
        --prefix="$FFBUILD_PREFIX"
        --libdir=lib
        --with-zlib-include="$FFBUILD_PREFIX/include"
        --with-zlib-lib="$FFBUILD_PREFIX/lib"
        --cross-compile-prefix="$FFBUILD_CROSS_PREFIX"
    )

    # GCC 14 может ругаться на строгие алиасы в старом коде OpenSSL
    export CFLAGS="$CFLAGS -fno-strict-aliasing"
    export CXXFLAGS="$CXXFLAGS -fno-strict-aliasing"

    ./Configure "${myconf[@]}" "$CFLAGS" "$LDFLAGS"

    make -j$(nproc) build_sw $MAKE_V
    make install_sw DESTDIR="$FFBUILD_DESTDIR"

    # OpenSSL 3.x иногда создает файлы lib64 или специфичные имена. 
    # Убедимся, что имена стандартные для FFmpeg
    if [[ -f "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib64/libssl.a" ]]; then
        cp -r "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib64/." "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/"
    fi
}

ffbuild_libs() {
    # Эти флаги нужны FFmpeg, чтобы слинковаться с libcrypto.a и libssl.a
    echo "-lssl -lcrypto -lws2_32 -lgdi32 -lcrypt32 -lbcrypt -lz"
}

ffbuild_configure() {
    echo "--enable-openssl"
}
