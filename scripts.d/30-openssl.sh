#!/bin/bash

SCRIPT_REPO="https://github.com/openssl/openssl.git"
SCRIPT_COMMIT="d099e33e5733bb9d3975fc4f3ac4a85b6ed1a4cb"

ffbuild_depends() {
    echo base
    echo zlib
}

ffbuild_enabled() {
    [[ $VARIANT == nonfree* ]] || return 0
    return 0
}

ffbuild_dockerdl() {
set -xe
    default_dl .

    # Список субмодулей, которые нам НЕ нужны (экономит сотни мегабайт трафика и места)
    # FORBIDDEN_SUBMODULES=(
        # "wycheproof" "tlslite-ng" "tlsfuzzer" "python-ecdsa" 
        # "pyca-cryptography" "pkcs11-provider" "oqs-provider" "krb5" "gost-engine"
    # )

    # if [[ -f ".gitmodules" ]]; then
        # for sub in "${FORBIDDEN_SUBMODULES[@]}"; do
            # local sub_path=$(git config -f .gitmodules --get-regexp "submodule\..*\.path" | grep "$sub" | awk '{print $2}' || echo "")
            # if [[ -n "$sub_path" ]]; then
                # log_debug "De-initializing and ignoring submodule: $sub_path"
                # git submodule deinit -f "$sub_path" 2>/dev/null || true
                # git config -f .gitmodules --remove-section "submodule.$sub" 2>/dev/null || true
            # fi
            # echo "rm -rf $sub external/$sub 2>/dev/null || true"
        # done
    # fi

    # Запускаем клонирование оставшихся (скачается только cloudflare-quiche)
    # echo "git-submodule-clone"

    # Вырезаем тяжелый тестовый и демонстрационный мусор
    echo "rm -rf test apps/demo doc/designs"
}

ffbuild_dockerbuild() {
    set -e

    cd "/build/$STAGENAME"
    local REAL_ROOT=$(find . -maxdepth 2 -name "Configure" -exec dirname {} \; | head -n 1)
    if [[ -n "$REAL_ROOT" ]]; then
        cd "$REAL_ROOT"
    fi

    # Фикс для QUIC
    # sed -i '1i#ifndef SIO_UDP_NETRESET\n#define SIO_UDP_NETRESET _WSAIOW(IOC_VENDOR, 15)\n#endif' include/internal/sockets.h
    find . -name "quic_reactor.c" -o -name "sockets.h" | xargs sed -i '1i #ifndef SIO_UDP_NETRESET\n#define SIO_UDP_NETRESET _WSAIOW(IOC_VENDOR, 15)\n#endif'

    # нужно передать только чистые имена команд без ccache и без префикса
    local CC="${FFBUILD_TOOLCHAIN}-gcc"
    local CXX="${FFBUILD_TOOLCHAIN}-g++"
    local AR="${FFBUILD_CROSS_PREFIX}ar"
    local RANLIB="${FFBUILD_CROSS_PREFIX}ranlib"

    local myconf=(
        threads # adding '-static' flag disables that, don't use it
        no-tests
        no-apps
        no-legacy
        no-unit-test
        no-async
        no-docs
        # ---- пытаемся очистить crypto/ folder----
        no-comp      # сжатие будет через zlib
        no-idea      # crypto/idea (Устаревший)
        no-md2       # crypto/md2  (Древний и небезопасный)
        no-md4       # crypto/md4  (Древний)
        no-rc2       # crypto/rc2  (Заменяется AES)
        no-rc4       # crypto/rc4  (Потоковый шифр RC4)
        no-rc5       # crypto/rc5  (Не используется)
        # no-bf        # crypto/bf   (Blowfish)
        no-cast      # crypto/cast (Cast-128)
        no-seed      # crypto/seed
        no-aria      # crypto/aria (Корейский стандарт шифрования)
        # no-camellia  # crypto/camellia
        no-sm2       # crypto/sm2  (Китайский нац. стандарт)
        no-sm3       # crypto/sm3  (Китайский хэш)
        no-sm4       # crypto/sm4  (Китайский шифр)
        # no-blake2    # blake2 (В FFmpeg есть свой встроенный)
        # no-whirlpool # crypto/whrlpool
        # no-rmd160    # RIPEMD-160
        # no-mdc2      # crypto/mdc2
        # no-srp       # crypto/srp (Secure Remote Password, для TLS не нужен)
        # no-cms       # crypto/cms (Cryptographic Message Syntax, почта/токены)
        # no-cmp       # crypto/cmp (Certificate Management Protocol)
        # no-crmf      # crypto/crmf
        # no-ocsp      # crypto/ocsp (Проверка сертификатов онлайн)
        # no-ct        # crypto/ct   (Certificate Transparency)
        # no-ts        # crypto/ts   (Time Stamping)
        # no-scrypt    # scrypt KDF
        # no-argon2    # argon2 KDF

        # Пост-квантотмы OpenSSL 3.4+, которые весят слишком много:
        # no-ml-dsa    # crypto/slh_dsa и ml_dsa
        # no-ml-kem    # crypto/ml_kem
        # --------------------------------------------
        enable-camellia
        enable-ec
        enable-srp
        --prefix="$FFBUILD_PREFIX"
        --libdir=lib
        --with-zlib-include="$FFBUILD_PREFIX/include"
        --with-zlib-lib="$FFBUILD_PREFIX/lib"
        --cross-compile-prefix="$FFBUILD_CROSS_PREFIX"
        --openssldir="$FFBUILD_PREFIX/etc/ssl"
    )

    if has_library "zstd"; then
        log_info "ZSTD library detected. Building with ZSTD support..."
        myconf+=( "enable-zstd" )
    fi

    if has_library "z"; then
        log_info "ZLib library detected. Building with ZLib support..."
        myconf+=( "zlib" )
    fi

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( shared zlib-dynamic pic ) || \
        myconf+=( no-shared zlib )

    if [[ $TARGET == win64 ]]; then
        myconf+=( mingw64 )
    elif [[ $TARGET == linux64 ]]; then
        myconf+=( linux-x86_64 )
    fi

    ./Configure "${myconf[@]}" \
        "$CFLAGS -fno-strict-aliasing -Wno-overflow ${USELTO}${USELTO_C}" \
        "$CPPFLAGS" \
        "$LDFLAGS ${USELTO}" \
        "$LIBS" || return 1

    make -j$(nproc) build_sw $MAKE_V || return 1
    make install_sw DESTDIR="$FFBUILD_DESTDIR" || return 1

    # OpenSSL 3.x иногда создает файлы lib64 или специфичные имена. 
    # Убедимся, что имена стандартные для FFmpeg
    if [[ -d "$INSTALL_ROOT/lib64" ]]; then
        mkdir -p "$INSTALL_ROOT/lib"
        cp -rn "$INSTALL_ROOT/lib64/"* "$INSTALL_ROOT/lib/"
        rm -rf "$INSTALL_ROOT/lib64"
    fi

    local EXTRA_LIBS="-lz -lgdi32 -lcrypt32"
    for PC_FILE in "$PC_DIR"/{openssl,libcrypto,libssl}.pc; do
        [[ -f "$PC_FILE" ]] || continue
        if grep -q "^Libs.private:" "$PC_FILE"; then
            for lib in $EXTRA_LIBS; do
                grep -q -- "$lib" "$PC_FILE" || sed -i "/^Libs.private:/ s/$/ $lib/" "$PC_FILE"
            done
        else
            if grep -q "^Libs:" "$PC_FILE"; then
                sed -i "/^Libs:/ a Libs.private: $EXTRA_LIBS" "$PC_FILE"
            else
                sed -i "/^Version:/ a Libs.private: $EXTRA_LIBS" "$PC_FILE"
            fi
        fi
        if grep -q "^Cflags:" "$PC_FILE"; then
            sed -i 's|^Cflags:.*|Cflags: -I${includedir} -I${includedir}/openssl|' "$PC_FILE"
            log_info "Updated Cflags in $(basename "$PC_FILE")"
        else
            echo -e "\nCflags: -I\${includedir} -I\${includedir}/openssl" >> "$PC_FILE"
            log_info "Added missing Cflags line to $(basename "$PC_FILE")"
        fi
    done
}

ffbuild_libs() {
    echo "-lssl -lcrypto"
}

ffbuild_configure() {
    echo --enable-openssl
}

ffbuild_unconfigure() {
    echo --disable-openssl
}
