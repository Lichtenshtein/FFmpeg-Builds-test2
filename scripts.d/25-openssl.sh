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
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
    echo "git submodule --quiet update --init --recursive --depth=1"
}

ffbuild_dockerbuild() {
    # MinGW-w64 пока не знает про SIO_UDP_NETRESET (нужно для QUIC)
    # Вставляем дефайн в системный заголовок внутри OpenSSL
    sed -i '1i#ifndef SIO_UDP_NETRESET\n#define SIO_UDP_NETRESET _WSAIOW(IOC_VENDOR, 15)\n#endif' include/internal/sockets.h

    # Убираем префикс из имен инструментов, так как OpenSSL добавит его сам
    local CLEAN_CC="${CC#$FFBUILD_CROSS_PREFIX}"
    local CLEAN_CXX="${CXX#$FFBUILD_CROSS_PREFIX}"
    local CLEAN_AR="${AR#$FFBUILD_CROSS_PREFIX}"
    local CLEAN_RANLIB="${RANLIB#$FFBUILD_CROSS_PREFIX}"

    local myconf=(
        threads
        zlib
        no-shared
        no-tests
        no-apps
        no-legacy
        no-ssl3
        no-async # Важно для стабильности на MinGW
        enable-camellia
        enable-ec
        enable-srp
        --prefix="$FFBUILD_PREFIX"
        --libdir=lib
        --cross-compile-prefix="$FFBUILD_CROSS_PREFIX"
    )

    if [[ $TARGET == win64 ]]; then
        myconf+=( mingw64 )
    elif [[ $TARGET == win32 ]]; then
        myconf+=( mingw )
    fi

    # GCC 14 может ругаться на строгие алиасы в старом коде OpenSSL
    export CFLAGS="$CFLAGS -fno-strict-aliasing"
    export CXXFLAGS="$CXXFLAGS -fno-strict-aliasing"

    # Передаем "чистые" имена инструментов
    CC="$CLEAN_CC" CXX="$CLEAN_CXX" AR="$CLEAN_AR" RANLIB="$CLEAN_RANLIB" \
    ./Configure "${myconf[@]}" "$CFLAGS" "$LDFLAGS"

    make -j$(nproc) build_sw
    make install_sw DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    [[ $TARGET == win* ]] && return 0
    echo --enable-openssl
}
