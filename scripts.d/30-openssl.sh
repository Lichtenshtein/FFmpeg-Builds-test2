#!/bin/bash

SCRIPT_REPO="https://github.com/openssl/openssl.git"
SCRIPT_COMMIT="234845aaabbcfef5f58a00835f0383ceabe469b5"

ffbuild_depends() {
    echo base
    echo zlib
    echo zstd
}

ffbuild_enabled() {
    [[ $VARIANT == nonfree* ]] || return 0
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    # echo "git-submodule-clone"
    echo "rm -rf test apps/demo doc/designs"
}

ffbuild_dockerbuild() {
    set -e

    cd "/build/$STAGENAME"
    local REAL_ROOT=$(find . -maxdepth 2 -name "Configure" -exec dirname {} \; | head -n 1)
    if [[ -n "$REAL_ROOT" ]]; then
        cd "$REAL_ROOT"
    fi

    # Fix for QUIC
    find . -name "quic_reactor.c" -o -name "sockets.h" | xargs sed -i '1i #ifndef SIO_UDP_NETRESET\n#define SIO_UDP_NETRESET _WSAIOW(IOC_VENDOR, 15)\n#endif'

    # need to pass only pure command names without ccache and without prefix
    local CC="gcc"
    local CXX="g++"
    local AR="ar"
    local RANLIB="gcc-ranlib"

    local myconf=(
        threads # adding '-static' flag disables that, don't use it
        no-tests
        no-apps
        no-legacy
        no-unit-test
        no-async
        no-docs
        # ---- trying to clear crypto/ folder----
        no-idea      # crypto/idea (Deprecated)
        no-md2       # crypto/md2  (Ancient and insecure)
        no-md4       # crypto/md4  (Ancient)
        no-rc2       # crypto/rc2  (Replaced by AES)
        no-rc4       # crypto/rc4  (RC4 stream cipher)
        no-rc5       # crypto/rc5  (Not used)
        # no-bf        # crypto/bf   (Blowfish)
        no-cast      # crypto/cast (Cast-128)
        no-seed      # crypto/seed
        no-aria      # crypto/aria (Korean Encryption Standard)
        # no-camellia  # crypto/camellia
        no-sm2       # crypto/sm2  (Chinese National Standard)
        no-sm3       # crypto/sm3  (Chinese hash)
        no-sm4       # crypto/sm4  (Chinese cipher)
        # no-blake2    # blake2 (FFmpeg has its own built-in)
        # no-whirlpool # crypto/whrlpool
        # no-rmd160    # RIPEMD-160
        # no-mdc2      # crypto/mdc2
        # no-srp       # crypto/srp (Secure Remote Password, not needed for TLS)
        # no-cms       # crypto/cms (Cryptographic Message Syntax, mail/tokens)
        # no-cmp       # crypto/cmp (Certificate Management Protocol)
        # no-crmf      # crypto/crmf
        # no-ocsp      # crypto/ocsp (Check certificates online)
        # no-ct        # crypto/ct   (Certificate Transparency)
        # no-ts        # crypto/ts   (Time Stamping)
        # no-scrypt    # scrypt KDF
        # no-argon2    # argon2 KDF

        # OpenSSL 3.4+ post-quantums that weigh too much:
        # no-ml-dsa    # crypto/slh_dsa and ml_dsa
        # no-ml-kem    # crypto/ml_kem
        # --------------------------------------------
        enable-camellia
        enable-ec
        enable-srp
        enable-pie
        --prefix="$FFBUILD_PREFIX"
        --libdir=lib
        --cross-compile-prefix="$FFBUILD_CROSS_PREFIX"
    )

    if has_library "zstd"; then
        log_info "ZSTD library detected. Building with ZSTD support..."
        myconf+=( enable-zstd )
    fi

    if has_library "z"; then
        log_info "ZLib library detected. Building with ZLib support..."
        myconf+=(
            no-comp
            zlib
            --with-zlib-include="$FFBUILD_PREFIX/include"
            --with-zlib-lib="$FFBUILD_PREFIX/lib"
        )
    fi

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( shared pic ) || \
        myconf+=( no-shared )

    if [[ $TARGET == win64 ]]; then
        myconf+=(
            mingw64
            --openssldir="$FFBUILD_PREFIX/etc/ssl"
        )
    elif [[ $TARGET == linux64 ]]; then
        myconf+=(
            --openssldir=/etc/ssl
            linux-x86_64
            enable-tfo
        )
    fi

    ./Configure "${myconf[@]}" \
        "$CFLAGS -fno-strict-aliasing -Wno-overflow ${USELTO}${USELTO_C}" \
        "$CPPFLAGS" \
        "$LDFLAGS ${USELTO}${USELTO_L}" \
        "$LIBS" || return 1

    make -j$(nproc) build_sw $MAKE_V || return 1
    make install_sw DESTDIR="$FFBUILD_DESTDIR" || return 1

    # OpenSSL 3.x sometimes creates lib64 files or files with specific names
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
    [[ "${SEC_PROTO}" != "openssl" ]] && echo --disable-openssl || echo --enable-openssl
}

ffbuild_unconfigure() {
    echo --disable-openssl
}
