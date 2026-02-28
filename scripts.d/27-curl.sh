#!/bin/bash

SCRIPT_REPO="https://github.com/curl/curl.git"
SCRIPT_COMMIT="bcc8144b896a49738cd60cbbe8e4f8e6f70461ef"

ffbuild_depends() {
    echo openssl
    echo zlib
    echo zstd
    echo brotli
    echo libssh
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

    unset CFLAGS CPPFLAGS
    export CPPFLAGS="$CPPFLAGS -DLIBSSH_STATIC -DBROTLI_STATIC -I$FFBUILD_PREFIX/include -D_FORTIFY_SOURCE=2"
    export CFLAGS="-O3 -march=broadwell -mtune=broadwell -static-libgcc -static-libstdc++ -pipe -fstack-protector-strong"
    export LDFLAGS="$LDFLAGS -L$FFBUILD_PREFIX/lib -static"
    export LIBS="-lssh -lbrotlidec -lbrotlicommon -lzstd -lws2_32 -lcrypt32 -lwldap32 -lnormaliz -lbcrypt -liphlpapi"

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
        --with-brotli
        --without-libpsl
        --enable-doh
        # --enable-ech
        # --with-ngtcp2
        # --with-nghttp3
        # --with-quiche
        # --with-nghttp2
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

    ./configure "${myconf[@]}" \
        CPPFLAGS="$CPPFLAGS" \
        CFLAGS="$CFLAGS" \
        LDFLAGS="$LDFLAGS" \
        LIBS="$LIBS"

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/libcurl.pc"
    if [[ -f "$PC_FILE" ]]; then
        log_info "Patching libcurl.pc for static linking..."
        sed -i '/Libs.private:/ s/$/ -lssh -lbrotlidec -lbrotlicommon -lws2_32 -lcrypt32 -lwldap32 -lnormaliz -lbcrypt -liphlpapi/' "$PC_FILE"
    fi
}

ffbuild_configure() {
    echo --enable-libcurl
}

ffbuild_unconfigure() {
    echo --disable-libcurl
}
