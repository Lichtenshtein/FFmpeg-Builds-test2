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
    set -e
    # Генерируем configure, так как работаем с git-репозиторием
    autoreconf -fi

    # Выделяем из CFLAGS только флаги компилятора (без -D и -I)
    # Это сохранит -march=broadwell, -O3, -pipe и т.д.
    local CLEAN_CFLAGS=$(echo "$CFLAGS" | sed 's/-D[^ ]*//g; s/-I[^ ]*//g')
    # Формируем чистый CPPFLAGS, куда уйдут все макросы
    # Добавляем -I$FFBUILD_PREFIX/include обязательно, чтобы curl видел openssl/zlib
    local CLEAN_CPPFLAGS="-I$FFBUILD_PREFIX/include -D_FORTIFY_SOURCE=2 -DCURL_STATICLIB -DLIBSSH_STATIC -DBROTLI_STATIC"

    # Собираем системные либы для Windows (OpenSSL требует bcrypt и advapi32)
    # Порядок: curl -> ssh -> openssl -> [zstd, brotli, zlib] -> [системные]
    local CURL_LIBS="-lssh -lssl -lcrypto -lbrotlidec -lbrotlicommon -lzstd -lz -liconv -lcharset -lcrypt32 -lwldap32 -lnormaliz -liphlpapi -lws2_32 -ladvapi32"

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

    [[ "$USE_LTO" == "1" ]] && myconf+=( --enable-lto )

    ./configure "${myconf[@]}" \
        CPPFLAGS="$CLEAN_CPPFLAGS" \
        CFLAGS="$CLEAN_CFLAGS" \
        LDFLAGS="$LDFLAGS -static" \
        LIBS="$CURL_LIBS $LIBS" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    clean_la_files

    # local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/libcurl.pc"
    # if [[ -f "$PC_FILE" ]]; then
        # log_info "${SYNC_MARK} Patching libcurl.pc..."
        # sed -i "s|^Libs.private:.*|Libs.private: $CURL_LIBS $LIBS|" "$PC_FILE"
        # sed -i "/^Cflags:/ s/$/ -DCURL_STATICLIB/" "$PC_FILE"
    # fi

    get_deps_list
}

ffbuild_cppflags() {
    echo "-DCURL_STATICLIB"
}

ffbuild_configure() {
    echo --enable-libcurl
}

ffbuild_unconfigure() {
    echo --disable-libcurl
}
