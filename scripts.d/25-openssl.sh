#!/bin/bash

SCRIPT_REPO="https://github.com/openssl/openssl.git"
SCRIPT_COMMIT="67b5686b4419b4cb8caa502711c41815f5279751"

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

    # ПРИНУДИТЕЛЬНО возвращаемся в корень распаковки, если find завел нас не туда
    cd "/build/$STAGENAME"
    
    # Если OpenSSL лежит в подпапке (например, openssl-3.x), заходим в нее
    # Ищем конкретно файл Configure, который есть только у OpenSSL
    local REAL_ROOT=$(find . -maxdepth 2 -name "Configure" -exec dirname {} \; | head -n 1)
    if [[ -n "$REAL_ROOT" ]]; then
        cd "$REAL_ROOT"
    fi

    # Проверка, что мы в нужном месте
    if [[ ! -f "Configure" ]]; then
        log_error "CRITICAL: OpenSSL Configure script not found in $(pwd)"
        ls -F
        exit 1
    fi

    # MinGW-w64 пока не знает про SIO_UDP_NETRESET (нужно для QUIC)
    # Вставляем дефайн в системный заголовок внутри OpenSSL
    sed -i '1i#ifndef SIO_UDP_NETRESET\n#define SIO_UDP_NETRESET _WSAIOW(IOC_VENDOR, 15)\n#endif' include/internal/sockets.h

    # Для OpenSSL ВАЖНО очистить переменные инструментов, чтобы он использовал кросс-префикс
    local TARGET_OS=""
    if [[ $TARGET == win64 ]]; then
        TARGET_OS="mingw64"
    else
        TARGET_OS="mingw"
    fi

    # Настраиваем пути к Zlib, который мы собрали ранее
    export CPPFLAGS="-I$FFBUILD_PREFIX/include"
    export LDFLAGS="-L$FFBUILD_PREFIX/lib"

    ./Configure "$TARGET_OS" \
        --prefix="$FFBUILD_PREFIX" \
        --libdir=lib \
        --cross-compile-prefix="$FFBUILD_CROSS_PREFIX" \
        no-shared \
        no-tests \
        no-apps \
        no-unit-test \
        no-legacy\
        no-async \
        threads \
        enable-camellia \
        enable-ec \
        enable-srp \
        zlib \
        --with-zlib-include="$FFBUILD_PREFIX/include" \
        --with-zlib-lib="$FFBUILD_PREFIX/lib" \
        $CFLAGS $LDFLAGS

    # GCC 14 может ругаться на строгие алиасы в старом коде OpenSSL
    # export CFLAGS="$CFLAGS -fno-strict-aliasing"
    # export CXXFLAGS="$CXXFLAGS -fno-strict-aliasing"

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
