#!/bin/bash

SCRIPT_REPO="https://github.com/lexiforest/curl-impersonate.git"
SCRIPT_COMMIT="78ff740b21c0911d63c6ee31b55a11a7c2f293cf"

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
