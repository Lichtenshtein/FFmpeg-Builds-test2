#!/bin/bash

SCRIPT_REPO="https://github.com/gnutls/gnutls.git"
SCRIPT_COMMIT="3bc844849437e9bb927e10bc0abe5c2f8e18953b"

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

    echo "rm -rf tests fuzz doc po src/gl/tests devel/libtasn1/tests"

    local COMPONENT_NAME="gnutls"
    local PATCHES_DIR="${PATCHES_DIR}"
    local CUSTOM_FILES="${PATCHES_DIR}/${COMPONENT_NAME}/gnutls_asn.zip"

    if [[ -f "$CUSTOM_FILES" ]]; then
        log_info "Placing gnu files in lib/ from patches..."
        echo "unzip -qo $CUSTOM_FILES -d lib"
    else
        log_warn "Custom gnu files not found at $CUSTOM_FILES"
    fi
}

ffbuild_dockerbuild() {
    set -e

    sed -i 's/use_git=false/use_git=true/g' bootstrap || true

    # intercept the hook in bootstrap.conf and replace the --with-tests flag with --without-tests for ggl modules
    sed -i 's/--macro-prefix=ggl --with-tests/--macro-prefix=ggl --without-tests/g' bootstrap.conf || true

    # Remove the cligen.mk inclusion from Makefile.am, which was hanging automake
    sed -i '/cligen\.mk/d' Makefile.am || true

    # Remove the block of tests, documentation, and utilities so that configure doesn't even try to create them
    sed -i '/doc\/Makefile/,/doc\/scripts\/Makefile/d' configure.ac
    sed -i '/tests\/Makefile/,/fuzz\/Makefile/d' configure.ac
    sed -i '/src\/Makefile/d' configure.ac
    sed -i '/src\/gl\/Makefile/d' configure.ac
    sed -i '/src\/gl\/tests\/Makefile/d' configure.ac
    sed -i '/po\/Makefile.in/d' configure.ac

    # Clear the root Makefile.am from all deleted subfolders
    sed -i 's/^SUBDIRS = .*/SUBDIRS = gl lib/g' Makefile.am
    sed -i '/SUBDIRS +=/d' Makefile.am
    sed -i '/if ENABLE_DANE/,/endif/ { /SUBDIRS +=/s/+=/=/; /libdane/p; d }' Makefile.am

    ./bootstrap --no-git --gnulib-srcdir=gnulib

    local DEP_LIBS="-lws2_32 -lbcrypt -lcrypt32 -lncrypt"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-doc
        --disable-tools
        --disable-tests
        --disable-bash-tests
        --disable-cxx
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
        myconf+=( --with-zstd=link )
    fi
    if has_library "z"; then
        log_info "ZLib library detected. Building GnuTLS with ZLib support..."
        myconf+=( --with-zlib=link )
    fi
    if has_library "brotlienc"; then
        log_info "Brotli library detected. Building GnuTLS with Brotli support..."
        myconf+=( --with-brotli=link )
    fi

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --enable-shared --disable-static ) || \
        myconf+=( --disable-shared --enable-static )

    CFLAGS="$CFLAGS ${USELTO}${USELTO_C}" \
    CPPFLAGS="$CPPFLAGS -D_UCRT=1" \
    CXXFLAGS="$CXXFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="${LDFLAGS} ${USELTO}${USELTO_L} ${USELTO}${USELTO_L}" \
    LIBS="$LIBS $DEP_LIBS" \
    ./configure "${myconf[@]}" || return 1

    if command -v asn1Parser &> /dev/null; then
        log_info "Generating mock ASN.1 tables with valid structures..."
        asn1Parser lib/minitasn1/gnutls.asn lib/gnutls_asn1_tab.c
        asn1Parser lib/minitasn1/pkix.asn lib/pkix_asn1_tab.c
    elif [[ ! -f "lib/gnutls_asn1_tab.c" ]]; then
        log_info "Generating mock ASN.1 stubs with valid structures..."
        cat <<EOF > lib/gnutls_asn1_tab.c
#include <stddef.h>
const void *gnutls_asn1_tab = NULL;
EOF
        cat <<EOF > lib/pkix_asn1_tab.c
#include <stddef.h>
const void *pkix_asn1_tab = NULL;
EOF
        touch lib/gnutls_asn1_tab.c lib/pkix_asn1_tab.c
    elif [[ -f "lib/gnutls_asn1_tab.c" ]]; then
        # update file times
        touch lib/gnutls_asn1_tab.c lib/pkix_asn1_tab.c
    fi

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    for PC_FILE in "$PC_DIR"/gnutls.pc; do
        [[ -f "$PC_FILE" ]] || continue
        sed -i "s|^Cflags:.*|& -I\${includedir}/gnutls|" "$PC_FILE"
        log_info "Updated Cflags in $(basename "$PC_FILE")"
        sed -i 's/libzstd/zstd/g' "$PC_FILE"
        sed -i 's/  */ /g' "$PC_FILE"
    done

    # try to resolve future symbol collisions with openssl
    # ${OBJCOPY} --localize-symbol=strndup libgnutls.${lib_ext}
}

ffbuild_configure() {
    [[ "${SEC_PROTO}" != "gnutls" ]] && echo --disable-gnutls || echo --enable-gnutls
}

ffbuild_unconfigure() {
    echo --disable-gnutls
}
