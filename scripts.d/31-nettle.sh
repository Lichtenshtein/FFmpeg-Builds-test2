#!/bin/bash

SCRIPT_REPO="https://github.com/gnutls/nettle.git"
SCRIPT_COMMIT="b95548d9ce1ec3e9f258ecb82099abdc95bbdd46"

ffbuild_depends() {
    echo gmp
    echo openssl # may be enabled
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    # В Nettle используется .bootstrap вместо autogen.sh
    if [[ -f ".bootstrap" ]]; then
        chmod +x .bootstrap
        ./.bootstrap
    fi

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-openssl
        # --disable-assembler # если будут ошибки в x86_64/*.asm
        --disable-documentation
        # --enable-mini-gmp # enable mini-gmp, used instead of libgmp
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    CFLAGS="$CFLAGS ${USELTO}${USELTO_C}" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    for PC_FILE in "$PC_DIR"/{nettle,hogweed}.pc; do
        [[ -f "$PC_FILE" ]] || continue
        sed -i 's|^Cflags:.*|Cflags: -I${includedir} -I${includedir}/nettle|' "$PC_FILE"
        log_info "Updated Cflags in $(basename "$PC_FILE")"
    done
}

