#!/bin/bash

SCRIPT_REPO="https://github.com/curl/curl.git"
SCRIPT_COMMIT="bcc8144b896a49738cd60cbbe8e4f8e6f70461ef"

ffbuild_depends() {
    echo openssl
    echo zlib
    echo zstd
    echo brotli
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    # Генерируем configure, так как работаем с git-репозиторием
    autoreconf -fi

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --target="$FFBUILD_TOOLCHAIN"
        --with-sysroot="$FFBUILD_SYSROOT"
        --disable-shared
        --enable-static
        --disable-debug
        --enable-optimize
        --enable-threaded-resolver
        --enable-ipv6
        --with-zlib
        --with-zstd
        --with-openssl
        --with-libssh
        --enable-doh
        --enable-cookies
        --enable-aws
        --enable-ntlm
        --enable-rtsp
        --enable-http
        --enable-proxy
        --enable-websockets
        --disable-ldap
        --disable-ldaps
        --disable-manual
        --disable-docs
    )

    # Принудительная статическая линковка зависимостей
    export LIBS="-lws2_32 -lcrypt32 -lwldap32 -lnormaliz -lbcrypt"

    ./configure "${myconf[@]}" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Патчим .pc файл для корректной линковки FFmpeg с curl
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/libcurl.pc"
    if [[ -f "$PC_FILE" ]]; then
        log_info "Patching libcurl.pc for static linking..."
        # Гарантируем наличие всех системных библиотек Windows в Libs.private
        sed -i '/Libs.private:/ s/$/ -lws2_32 -lcrypt32 -lwldap32 -lnormaliz -lbcrypt/' "$PC_FILE"
    fi
}

ffbuild_configure() {
    echo --enable-libcurl
}

ffbuild_unconfigure() {
    echo --disable-libcurl
}
