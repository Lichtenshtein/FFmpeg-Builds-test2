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

    autoreconf -fi

    export PKG_CONFIG_PATH="$FFBUILD_PREFIX/lib/pkgconfig:$FFBUILD_PREFIX/share/pkgconfig:$PKG_CONFIG_PATH"

    # Выделяем из CFLAGS только флаги компилятора (без -D и -I)
    local CLEAN_CFLAGS=$(echo "$CFLAGS" | sed 's/-[DU][^ ]*//g; s/-I[^ ]*//g')

    # Собираем системные либы для Windows (OpenSSL требует bcrypt и advapi32)
    # Порядок: curl -> (+crypto, quiche) -> ssh -> openssl -> [zstd, brotli, zlib] -> [системные]
    local DEP_LIBS="-lssh -lquiche -lnghttp2 -lssl -lcrypto -lzstd -lbrotlidec -lbrotlicommon -lz"
    local WIN_LIBS="-lcrypt32 -lwldap32 -lnormaliz -liphlpapi -lws2_32 -lbcrypt -ladvapi32 -luser32 -lntdll"
    local ALL_LIBS="$DEP_LIBS $WIN_LIBS $LIBS"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --target="$FFBUILD_TOOLCHAIN"
        --with-sysroot="$FFBUILD_SYSROOT"
        --disable-debug
        --enable-optimize
        --enable-threaded-resolver
        --enable-ipv6
        # --with-openssl
        # --with-ngtcp2
        # --with-nghttp3
        # --with-quiche
        # --with-nghttp2
        --with-openssl="$FFBUILD_PREFIX"
        --with-nghttp2="$FFBUILD_PREFIX"
        --with-quiche="$FFBUILD_PREFIX" # ngtcp2 + nghttp3
        --with-libssh="$FFBUILD_PREFIX"
        --with-zlib
        --with-zstd
        --with-brotli
        --with-pic
        --without-libpsl
        --enable-doh
        --enable-ech
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

    export static_flags=""
    export self_static_flags=""

    if [[ "${PREFER_SHARED}" != "1" ]]; then
        static_flags="-DLIBSSH_STATIC -DBROTLI_STATIC"
        self_static_flags="-DCURL_STATICLIB"
        myconf+=( --enable-static --disable-shared )
    else
        myconf+=( --disable-static --enable-shared )
    fi

    CFLAGS="$CLEAN_CFLAGS ${USELTO}" \
    CPPFLAGS="$CPPFLAGS $self_static_flags $static_flags" \
    CXXFLAGS="$CXXFLAGS $self_static_flags $static_flags ${USELTO}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    LIBS="$ALL_LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    local PC_FILE="$PC_DIR/libcurl.pc"
    if [[ -f "$PC_FILE" ]]; then
        # Очищаем Libs (оставляем только саму либу)
        sed -i "s|^Libs:.*|Libs: -L\${libdir} -lcurl|" "$PC_FILE"
        # Очищаем Requires, чтобы pkg-config не падал из-за отсутствующих имен .pc
        sed -i "s|^Requires:.*|Requires:|" "$PC_FILE"
        sed -i "s|^Requires.private:.*|Requires.private:|" "$PC_FILE"
        # Перезаписываем Libs.private
        sed -i "/^Libs\.private:/d" "$PC_FILE"
        echo "Libs.private: $DEP_LIBS $WIN_LIBS" >> "$PC_FILE"
        # Убеждаемся, что макрос статики на месте
        if [[ -n "$self_static_flags" ]]; then
            if ! grep -qF -- "$self_static_flags" "$PC_FILE"; then
                sed -i "/^Cflags:/ s/$/ $self_static_flags/" "$PC_FILE"
            fi
        fi
    fi
}

ffbuild_libs() {
    echo "-lcrypt32 -lwldap32 -lnormaliz -liphlpapi"
}

ffbuild_cppflags() {
    echo "$self_static_flags"
}

ffbuild_configure() {
    echo --enable-libcurl
}

ffbuild_unconfigure() {
    echo --disable-libcurl
}
