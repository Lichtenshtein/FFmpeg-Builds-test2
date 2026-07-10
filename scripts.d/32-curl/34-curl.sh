#!/bin/bash

SCRIPT_REPO="https://github.com/curl/curl.git"
SCRIPT_COMMIT="d054f386dd77ed02f6d7513e0464e414948d93df"

ffbuild_depends() {
    # echo openssl
    echo zlib
    echo zstd
    echo brotli
    echo libssh
    echo quiche
    echo nghttp2
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

    if [[ $TARGET == win64 ]]; then
        sed -i 's/include <sys\/socket.h>/include <winsock2.h>/g' configure
    fi

    export PKG_CONFIG_PATH="$FFBUILD_PREFIX/lib/pkgconfig:$FFBUILD_PREFIX/share/pkgconfig"
    export PKG_CONFIG_ALLOW_CROSS=1

    # Выделяем из CFLAGS только флаги компилятора (без -D и -I)
    local CLEAN_CFLAGS=$(echo "$CFLAGS" | sed 's/-[DU][^ ]*//g; s/-I[^ ]*//g')

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --target="$FFBUILD_TOOLCHAIN"
        --with-sysroot="$FFBUILD_SYSROOT"
        --disable-debug
        --enable-optimize
        --enable-threaded-resolver
        --enable-ipv6
        --with-pic
        --without-libpsl
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
        # other secure protocols; first=higher priority
        # --with-schannel
        # --with-gnutls
        # --with-mbedtls
    )

    if has_library "ssl"; then
        log_info "OpenSSL library detected. Building with OpenSSL support..."
        myconf+=( --with-openssl ) # lso for AWS-LC, BoringSSL, LibreSSL, and quictls
        local SSL_LIBS="-lssl -lcrypto"
    fi
    if has_library "zstd"; then
        log_info "ZSTD library detected. Building with ZSTD support..."
        myconf+=( --with-zstd )
        local ZSTD_LIBS="-lzstd"
    fi
    if has_library "z"; then
        log_info "ZLib library detected. Building with ZLib support..."
        myconf+=( --with-zlib )
        local Z_LIBS="-lz"
    fi
    if has_library "brotlienc"; then
        log_info "Brotli library detected. Building with Brotli support..."
        myconf+=( --with-brotli )
        local BROTLI_LIBS="-lbrotlidec -lbrotlicommon"
    fi
    if has_library "ssh"; then
        log_info "SSH library detected. Building with SSH support..."
        myconf+=( --with-libssh="$FFBUILD_PREFIX" )
        local SSH_LIBS="-lssh"
    fi
    if has_library "quiche"; then
        log_info "Quiche library detected. Building with Quiche support..."
        # ngtcp2 + nghttp3
        myconf+=(
            --with-quiche="$FFBUILD_PREFIX"
            --enable-doh
            --enable-ech
        )
        local QUICHE_LIBS="-lquiche"
    fi
    if has_library "nghttp2"; then
        log_info "nghttp2 library detected. Building with nghttp2 support..."
        myconf+=( --with-nghttp2="$FFBUILD_PREFIX" )
        local HTTP2_LIBS="-lnghttp2"
    fi

    # Собираем системные либы для Windows (OpenSSL требует bcrypt и advapi32)
    # Порядок: curl -> (+crypto, quiche) -> ssh -> openssl -> [zstd, brotli, zlib] -> [системные]
    local DEP_LIBS="${SSH_LIBS} ${QUICHE_LIBS} ${HTTP2_LIBS} ${SSL_LIBS} ${ZSTD_LIBS} ${BROTLI_LIBS} ${Z_LIBS}"
    local WIN_LIBS="-luserenv -lcrypt32 -liphlpapi -lntdll -lsetupapi"

    export static_flags=""
    export self_static_flags=""

    if [[ "${PREFER_SHARED}" != "1" ]]; then
        static_flags="-DLIBSSH_STATIC -DBROTLI_STATIC -DNGHTTP2_STATICLIB"
        self_static_flags="-DCURL_STATICLIB"
        myconf+=( --enable-static --disable-shared )
    else
        myconf+=( --disable-static --enable-shared )
    fi

    # curl и gcc 15.2 захлёбываются на LTO и уходят в segmentation fault при компиляции бинарника
    # [[ "${USE_LTO}" = "1" ]] && local LTO_FIX=" -fno-ipa-icf"

    # конфликт boringssl и openssl; -Wl,--allow-multiple-definition

    CFLAGS="$CLEAN_CFLAGS ${USELTO}${USELTO_C}${LTO_FIX}" \
    CPPFLAGS="$CPPFLAGS $self_static_flags $static_flags" \
    CXXFLAGS="$CXXFLAGS $self_static_flags $static_flags ${USELTO}${USELTO_C}${LTO_FIX}" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}${LTO_FIX}" \
    LIBS="$DEP_LIBS $WIN_LIBS $LIBS" \
    ./configure "${myconf[@]}" || return 1

    # make -j$(nproc) $MAKE_V || return 1
    # make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    # собираем только библиотеку так как segmentation fault происходит на curl.exe
    make -C lib -j$(nproc) $MAKE_V
    make -C lib install DESTDIR="$FFBUILD_DESTDIR"
    make -C include install DESTDIR="$FFBUILD_DESTDIR"

    # Устанавливаем pkg-config файл вручную (он генерируется в корне)
    mkdir -p "$PC_DIR"
    cp libcurl.pc "$PC_DIR/"

    local PC_FILE="$PC_DIR/libcurl.pc"
    if [[ -f "$PC_FILE" ]]; then
        # Очищаем Libs (оставляем только саму либу)
        sed -i "s|^Libs:.*|Libs: -L\${libdir} -lcurl|" "$PC_FILE"
        # Очищаем Requires, чтобы pkg-config не падал из-за отсутствующих имен .pc
        sed -i "s|^Requires:.*|Requires:|" "$PC_FILE"
        sed -i "s|^Requires.private:.*|Requires.private:|" "$PC_FILE"
        # Перезаписываем Libs.private; хз куда пропадает -lz
        sed -i "/^Libs\.private:/d" "$PC_FILE"
        echo "Libs.private: $DEP_LIBS $WIN_LIBS" >> "$PC_FILE"
        sed -i "s|^Cflags:.*|& -I\${includedir}/curl|" "$PC_FILE"
        # Убеждаемся, что макрос статики на месте
        if [[ -n "$self_static_flags" ]]; then
            if ! grep -qF -- "$self_static_flags" "$PC_FILE"; then
                sed -i "/^Cflags:/ s/$/ $self_static_flags/" "$PC_FILE"
            fi
        fi
    fi
}

# that's odd; i thought ffmpeg used to support libcurl natively

# ffbuild_libs() {
    # echo "-lquiche -lnghttp2 -lcrypt32 -lwldap32 -lnormaliz -liphlpapi"
# }

# ffbuild_cppflags() {
    # echo "$static_flags $self_static_flags"
# }

# ffbuild_configure() {
    # echo --enable-libcurl
# }

# ffbuild_unconfigure() {
    # echo --disable-libcurl
# }
