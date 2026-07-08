#!/bin/bash

SCRIPT_REPO="https://github.com/gpg/libgcrypt.git"
SCRIPT_COMMIT="35f4e5abf22c8a1cb07314914d29b11c63decb5b"

ffbuild_depends() {
    echo libgpg-error
}

ffbuild_enabled() {
    return 1
}

ffbuild_dockerdl() {
    default_dl .
    echo "rm -rf tests"
}

ffbuild_dockerbuild() {
    set -e

    ./autogen.sh || return 1

    local DEP_LIBS="-lgpg-error"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --with-pic
        --disable-doc
        --with-gpg-error-prefix="$FFBUILD_PREFIX"
    )

    if [[ "${USE_AVX512}" != "1" ]]; then
        myconf+=( --disable-avx512-support )
    fi

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    CFLAGS="$CFLAGS ${USELTO:-}${USELTO_C:-}" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS ${USELTO:-}${USELTO_C:-}" \
    LDFLAGS="$LDFLAGS ${USELTO:-}${USELTO_L:-}" \
    LIBS="$DEP_LIBS $LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" bin_PROGRAMS="" || return 1

    local PC_FILE="$PC_DIR/libgcrypt.pc"

    if [[ ! -f "$PC_FILE" ]]; then
        log_warn "libgcrypt.pc not found. Generating fallback pkg-config descriptor."
        {
            echo "prefix=${FFBUILD_PREFIX}"
            echo "exec_prefix=\${prefix}"
            echo "libdir=\${exec_prefix}/lib"
            echo "includedir=\${prefix}/include"
            echo ""
            echo "Name: libgcrypt"
            echo "Description: GnuPG cryptographic library"
            echo "Version: 1.11.3"
            echo "Libs: -L\${libdir} -lgcrypt"
            echo "Libs.private: $DEP_LIBS"
            echo "Cflags: -I\${includedir}"
        } > "$PC_FILE"
    else
        sed -i "s|^prefix=.*|prefix=${FFBUILD_PREFIX}|" "$PC_FILE"
        if [[ $TARGET == win64 ]]; then
            if ! grep -qF -- "-lws2_32" "$PC_FILE"; then
                sed -i "/^Libs:/ s/$/ -lws2_32/" "$PC_FILE"
            fi
        fi
        if ! grep -qF -- "-lstdc++" "$PC_FILE"; then
            sed -i "/^Libs.private:/ s/$/ -lstdc++/" "$PC_FILE"
        fi
    fi
}
