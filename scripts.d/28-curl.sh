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
    local CLEAN_CFLAGS=$(echo "$CFLAGS" | sed 's/-[DU][^ ]*//g; s/-I[^ ]*//g')
    # Формируем чистый CPPFLAGS, куда уйдут все макросы
    # Добавляем -I$FFBUILD_PREFIX/include обязательно, чтобы curl видел openssl/zlib

    # Собираем системные либы для Windows (OpenSSL требует bcrypt и advapi32)
    # Порядок: curl -> ssh -> openssl -> [zstd, brotli, zlib] -> [системные]
    local DEP_LIBS="-lssh -lssl -lcrypto -lzstd -lbrotlienc -lbrotlidec -lbrotlicommon -lz"
    local WIN_LIBS="-lcrypt32 -lwldap32 -lnormaliz -liphlpapi $LIBS"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --target="$FFBUILD_TOOLCHAIN"
        --with-sysroot="$FFBUILD_SYSROOT"
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

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )
    [[ "$USE_LTO" == "1" ]] && myconf+=( --enable-lto )

    local static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DLIBSSH_STATIC -DBROTLI_STATIC" && self_static_flags="-DCURL_STATICLIB"

    CFLAGS="$CLEAN_CFLAGS" \
    CPPFLAGS="$CPPFLAGS $self_static_flags $static_flags" \
    CXXFLAGS="$CXXFLAGS $self_static_flags $static_flags" \
    LDFLAGS="$LDFLAGS" \
    LIBS="$DEP_LIBS $WIN_LIBS" \
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
        if ! grep -q "$self_static_flags" "$PC_FILE"; then
            sed -i "/^Cflags:/ s/$/ $self_static_flags/" "$PC_FILE"
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
