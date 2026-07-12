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

    # Fixing type incompatibility in getsockopt for Windows MinGW
    if grep -q "getsockopt" lib/cddb_net.c; then
        log_info "Patching getsockopt calls in cddb_net.c for Win32 API compatibility..."
        # Cast &rv to type (char *)&rv, as required by winsock2.h
        sed -i 's|&rv, &l|(char *)\&rv, \&l|g' lib/cddb_net.c
    fi

    # Fixing header guard warnings/errors in header files (LOH -> LOG)
    if [[ -f "include/cddb/cddb_log.h" ]]; then
        log_info "Patching header guards typos..."
        sed -i 's|CDDB_LOH_H|CDDB_LOG_H|g' include/cddb/cddb_log.h
        sed -i 's|CDDB_LOH_NI_H|CDDB_LOG_NI_H|g' include/cddb/cddb_log_ni.h
    fi

    cat <<EOF > include/cddb/cddb_regex.h
#ifndef CDDB_REGEX_H
#define CDDB_REGEX_H 1
#include <stdlib.h>

void cddb_regex_init(void);
void cddb_regex_destroy(void);
int cddb_regex_get_int(const char *s, void *matches, int idx);
unsigned long cddb_regex_get_hex(const char *s, void *matches, int idx);
double cddb_regex_get_float(const char *s, void *matches, int idx);
char *cddb_regex_get_string(const char *s, void *matches, int idx);

#endif
EOF

    cat <<EOF > lib/cddb_regex.c
#include "cddb/cddb_regex.h"

void cddb_regex_init(void) {}
void cddb_regex_destroy(void) {}
int cddb_regex_get_int(const char *s, void *matches, int idx) { return 0; }
unsigned long cddb_regex_get_hex(const char *s, void *matches, int idx) { return 0; }
double cddb_regex_get_float(const char *s, void *matches, int idx) { return 0.0; }
char *cddb_regex_get_string(const char *s, void *matches, int idx) { return NULL; }
EOF

    log_info "Generating configure script via autoreconf..."
    autoreconf -fi

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
    LIBS="${ICONV_LIBS} $LIBS" \
    ./configure "${myconf[@]}" || return 1

    if [[ -f "Makefile" ]]; then
        sed -i 's|SUBDIRS = include lib examples po|SUBDIRS = include lib po|g' Makefile
    fi

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
