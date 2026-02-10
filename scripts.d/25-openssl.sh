#!/bin/bash

SCRIPT_REPO="https://github.com/openssl/openssl.git"
SCRIPT_COMMIT="openssl-3.5.4"
SCRIPT_TAGFILTER="openssl-3.5.*"

ffbuild_depends() {
    echo base
    echo zlib
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git submodule update --init --recursive --depth=1"
}

ffbuild_dockerbuild() {
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

    export CFLAGS="$CFLAGS -fno-strict-aliasing"
    export CXXFLAGS="$CXXFLAGS -fno-strict-aliasing"

    # Передаем "чистые" имена инструментов
    CC="$CLEAN_CC" CXX="$CLEAN_CXX" AR="$CLEAN_AR" RANLIB="$CLEAN_RANLIB" \
    ./Configure "${myconf[@]}" "$CFLAGS" "$LDFLAGS"

    make -j$(nproc) build_sw
    make install_sw DESTDIR="$FFBUILD_DESTDIR"

    # Копируем результат в префикс текущего слоя
    cp -r "$FFBUILD_DESTDIR$FFBUILD_PREFIX"/. "$FFBUILD_PREFIX"/
}

ffbuild_configure() {
    [[ $TARGET == win* ]] && return 0
    echo --enable-openssl
}
