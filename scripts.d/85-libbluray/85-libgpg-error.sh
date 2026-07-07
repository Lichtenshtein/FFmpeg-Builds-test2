#!/bin/bash

SCRIPT_REPO="https://github.com/gpg/libgpg-error.git"
SCRIPT_COMMIT="bfdf7b0b7b62f4463451a7d5f8408cec75520dca"

ffbuild_depends() {
    echo libiconv
    echo gettext
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    # Patching the implicit declaration of inet_pton under mingw
    log_info "Patching missing ws2tcpip.h include for inet_pton in logging.c..."
    if [[ -f "src/logging.c" ]]; then
        sed -i '/#include <config.h>/a #ifdef _WIN32\n# include <ws2tcpip.h>\n#endif' src/logging.c
    fi

    local DEP_LIBS=" -lintl -liconv -lcharset"
    if [[ $TARGET == win64 ]]; then
        DEP_LIBS="-lws2_32$DEP_LIBS"
    fi

    ./autogen.sh || return 1

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --with-pic
        --disable-doc
        --disable-languages
        --disable-tests
        --disable-install-gpg-error-config
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    local target_cppflags="$CPPFLAGS"
    if [[ $TARGET == win64 ]]; then
        target_cppflags="$target_cppflags -DNTDDI_VERSION=0x0A000000"
    fi

    CFLAGS="$CFLAGS ${USELTO:-}${USELTO_C:-}" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS ${USELTO:-}${USELTO_C:-}" \
    LDFLAGS="$LDFLAGS ${USELTO:-}${USELTO_L:-}" \
    LIBS="$DEP_LIBS $LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" bin_PROGRAMS="" bin_SCRIPTS="" || return 1

    local PC_FILE="$PC_DIR/gpg-error.pc"

    if [[ ! -f "$PC_FILE" ]]; then
        log_warn "libgpg-error.pc not found. Generating fallback pkg-config descriptor."
        {
            echo "prefix=${FFBUILD_PREFIX}"
            echo "exec_prefix=\${prefix}"
            echo "libdir=\${exec_prefix}/lib"
            echo "includedir=\${prefix}/include"
            echo ""
            echo "Name: libgpg-error"
            echo "Description: GnuPG error reporting library"
            echo "Version: 1.61"
            echo "Libs: -L\${libdir} -lgpg-error"
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
