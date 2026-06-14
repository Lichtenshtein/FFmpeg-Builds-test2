#!/bin/bash

SCRIPT_REPO="https://github.com/gnutls/gnutls.git"
SCRIPT_COMMIT="0b9fcb47c734191695b7b7812a0ba30a5c712b9f"

ffbuild_depends() {
    echo zlib
    echo zstd
    echo gmp
    echo nettle
    echo brotli
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    # echo "git-submodule-clone"
    echo "git-mini-clone \"https://gitlab.com/libidn/gnulib-mirror.git\" \"master\" gnulib"
    echo "git-mini-clone \"https://gitlab.com/gnutls/libtasn1.git\" \"master\" devel/libtasn1"
    echo "rm -rf tests fuzz doc po src/gl/tests gnulib/tests devel/libtasn1/tests"
}

ffbuild_dockerbuild() {
    set -e

    # Удаляем блок тестов, документации и утилит, чтобы configure даже не пытался их создать
    sed -i '/doc\/Makefile/,/doc\/scripts\/Makefile/d' configure.ac
    sed -i '/tests\/Makefile/,/fuzz\/Makefile/d' configure.ac
    sed -i '/src\/Makefile/d' configure.ac
    sed -i '/src\/gl\/Makefile/d' configure.ac
    sed -i '/src\/gl\/tests\/Makefile/d' configure.ac
    sed -i '/po\/Makefile.in/d' configure.ac

    # Очищаем корневой Makefile.am от всех вырезанных подпапок
    sed -i 's/^SUBDIRS = .*/SUBDIRS = gl lib/g' Makefile.am
    sed -i '/SUBDIRS +=/d' Makefile.am
    sed -i '/if ENABLE_DANE/,/endif/ { /SUBDIRS +=/s/+=/=/; /libdane/p; d }' Makefile.am

    ./bootstrap

    local DEP_LIBS="-lws2_32 -lbcrypt -lcrypt32 -lncrypt"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-doc
        --disable-tools
        --disable-tests
        --disable-bash-tests
        --disable-cxx
        --disable-guile
        --disable-libdane
        --disable-nls
        --disable-padlock
        --enable-hardware-acceleration
        --with-included-unistring
        --with-included-libtasn1
        --without-p11-kit
        --without-tpm
        --without-idn
        --disable-full-test-suite
    )

    if has_library "zstd"; then
        log_info "ZSTD library detected. Building GnuTLS with ZSTD support..."
        myconf+=( "--with-zstd=link" )
    fi
    if has_library "z"; then
        log_info "ZLib library detected. Building GnuTLS with ZLib support..."
        myconf+=( "--with-zlib=link" )
    fi
    if has_library "brotlienc"; then
        log_info "Brotli library detected. Building GnuTLS with Brotli support..."
        myconf+=( "--with-brotli=link" )
    fi

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --enable-shared --disable-static ) || \
        myconf+=( --disable-shared --enable-static )

    CFLAGS="$CFLAGS ${USELTO}${USELTO_C}" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    LIBS="$LIBS $DEP_LIBS" \
    ./configure "${myconf[@]}" || return 1

    log_info "Touching ASN.1 generated files to skip asn1Parser..."
    touch lib/pkix_asn1_tab.c
    touch lib/gnutls_asn1_tab.c

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    for PC_FILE in "$PC_DIR"/gnutls.pc; do
        [[ -f "$PC_FILE" ]] || continue
        sed -i "s|^Cflags:.*|& -I\${includedir}/gnutls|" "$PC_FILE"
        log_info "Updated Cflags in $(basename "$PC_FILE")"
    done
}

# only build as a dependency for other components

# ffbuild_configure() {
    # echo --enable-gnutls
# }

# ffbuild_unconfigure() {
    # echo --disable-gnutls
# }
