#!/bin/bash

SCRIPT_REPO="https://github.com/qyot27/libcddb.git"
SCRIPT_COMMIT="9719ce60dfe750c71df8d31fe58de0b55e17f48e"
SCRIPT_BRANCH="mingw-w64"

ffbuild_depends() {
    echo libiconv
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "rm -rf doc tests"
}

ffbuild_dockerbuild() {
    set -e

    if [[ -f "bootstrap" ]]; then
        chmod +x bootstrap
        ./bootstrap
    elif [[ -f "configure.ac" || -f "configure.in" ]]; then
        log_info "Generating configure script via autoreconf..."
        autoreconf -fi
    fi

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --with-pic
        --disable-maintainer-mode
        --without-cdio # loop dependency
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    if has_library "iconv"; then
        log_info "Iconv library detected. Building libcddb with Iconv support..."
        myconf+=( --with-iconv )
        local ICONV_LIBS="-liconv -lcharset"
    else
        log_warn "Iconv library not found. Building libcddb without Iconv..."
        myconf+=( --without-iconv )
    fi

    CFLAGS="$CFLAGS ${USELTO}${USELTO_C}" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS $DEP_LIBS ${USELTO}${USELTO_L}" \
    LIBS="$LIBS ${ICONV_LIBS}" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" bin_PROGRAMS="" || return 1

    mkdir -p "$PC_DIR"

    if [[ ! -f "${PC_DIR}/libcddb.pc" ]]; then
        cat <<EOF > "${PC_DIR}/libcddb.pc"
prefix=${FFBUILD_PREFIX}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: cddb
Description: CDDB server access library
Version: 1.3.2
Libs: -L\${libdir} -lcddb
Libs.private: ${ICONV_LIBS}
Cflags: -I\${includedir}
EOF
    fi
}
