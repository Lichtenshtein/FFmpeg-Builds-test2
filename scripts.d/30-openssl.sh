#!/bin/bash

SCRIPT_REPO="https://github.com/openssl/openssl.git"
SCRIPT_COMMIT="561a86e7832d244e62587240a22268f4a25ee1cd"
# SCRIPT_COMMIT="c9a9e5b10105ad850b6e4d1122c645c67767c341"

ffbuild_depends() {
    echo base
    echo zlib
}

ffbuild_enabled() {
    [[ $VARIANT == nonfree* ]] || return 0
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-submodule-clone"
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

    export CC="${CC/${FFBUILD_CROSS_PREFIX}/}"
    export CXX="${CXX/${FFBUILD_CROSS_PREFIX}/}"
    export AR="${AR/${FFBUILD_CROSS_PREFIX}/}"
    export RANLIB="${RANLIB/${FFBUILD_CROSS_PREFIX}/}"

    local myconf=(
        threads # adding '-static' flag disables that, don't use it
        no-tests
        no-apps
        no-legacy
        no-unit-test
        no-async
        no-docs
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
    if [[ -d "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib64" ]]; then
        mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib"
        cp -rn "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib64/"* "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/"
        rm -rf "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib64"
    fi

    local EXTRA_LIBS="-lz -lgdi32 -lcrypt32"
    for pc in "$PC_DIR"/{openssl,libcrypto,libssl}.pc; do
        [[ -f "$pc" ]] || continue
        if grep -q "^Libs.private:" "$pc"; then
            for lib in $EXTRA_LIBS; do
                grep -q -- "$lib" "$pc" || sed -i "/^Libs.private:/ s/$/ $lib/" "$pc"
            done
        else
            if grep -q "^Libs:" "$pc"; then
                sed -i "/^Libs:/ a Libs.private: $EXTRA_LIBS" "$pc"
            else
                sed -i "/^Version:/ a Libs.private: $EXTRA_LIBS" "$pc"
            fi
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
