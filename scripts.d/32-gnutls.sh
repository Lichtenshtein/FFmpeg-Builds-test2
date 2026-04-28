#!/bin/bash

SCRIPT_REPO="https://github.com/gnutls/gnutls.git"
SCRIPT_COMMIT="8366cd25ff81ddf27a7a5d885f64a3fdcc0c5125"

ffbuild_depends() {
    echo zlib
    echo zstd
    echo gmp
    echo nettle
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "git-submodule-clone"
}

ffbuild_dockerbuild() {
    set -e

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
        --with-zstd=link
        --with-zlib
        --disable-full-test-suite
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --enable-shared --disable-static ) || \
        myconf+=( --disable-shared --enable-static )

    CFLAGS="$CFLAGS ${USELTO}" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS ${USELTO}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    LIBS="$LIBS $DEP_LIBS" \
    ./configure "${myconf[@]}" || return 1

    log_info "Touching ASN.1 generated files to skip asn1Parser..."
    touch lib/pkix_asn1_tab.c
    touch lib/gnutls_asn1_tab.c
    touch lib/priority_options.h

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    # local PC_FILE="$PC_DIR/gnutls.pc"
    # if [[ -f "$PC_FILE" ]]; then
        # if ! grep -q "\-lbcrypt" "$PC_FILE"; then
            # sed -i "s/Libs.private:/& -lws2_32 -lbcrypt -lcrypt32 -lncrypt /" "$PC_FILE"
        # fi
    # fi
}

# only build as a dependency for other components

# ffbuild_configure() {
    # echo --enable-gnutls
# }

# ffbuild_unconfigure() {
    # echo --disable-gnutls
# }
