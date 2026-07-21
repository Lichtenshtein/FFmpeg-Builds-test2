#!/bin/bash

SCRIPT_REPO="https://github.com/gnutls/nettle.git"
SCRIPT_COMMIT="5dbdcef3d03195baf4d5871d43fa87e8f7c081e6"

ffbuild_depends() {
    echo gmp
    echo openssl # may be enabled
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "rm -rf examples testsuite tools"
}

ffbuild_dockerbuild() {
    set -e

    # Nettle uses .bootstrap instead of autogen.sh
    if [[ -f ".bootstrap" ]]; then
        chmod +x .bootstrap
        ./.bootstrap
    fi

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-openssl
        # --disable-assembler # if there are errors in x86_64/*.asm
        --disable-documentation
        # --enable-mini-gmp # enable mini-gmp, used instead of libgmp
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    CFLAGS="$CFLAGS ${USELTO}${USELTO_C}" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    for PC_FILE in "$PC_DIR"/{nettle,hogweed}.pc; do
        [[ -f "$PC_FILE" ]] || continue
        sed -i "s|^Cflags:.*|& -I\${includedir}/nettle|" "$PC_FILE"
        log_info "Updated Cflags in $(basename "$PC_FILE")"
    done
}

