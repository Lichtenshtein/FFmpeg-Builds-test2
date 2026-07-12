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

    # remove the conditional wrapper so that mask definitions are always available
    if [[ -f "lib/cddb_regex.h" ]]; then
        log_info "Forcing POSIX regex definitions in cddb_regex.h for Windows build..."
        sed -i 's|#ifdef HAVE_REGEX_H||g' include/cddb/cddb_regex.h
        sed -i 's|#endif /* HAVE_REGEX_H */||g' include/cddb/cddb_regex.h
    fi

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
    CPPFLAGS="$CPPFLAGS -DHAVE_REGEX_H=1" \
    CXXFLAGS="$CXXFLAGS ${USELTO}${USELTO_C}" \
    LDFLAGS="$LDFLAGS $DEP_LIBS ${USELTO}${USELTO_L}" \
    LIBS="${ICONV_LIBS} $LIBS" \
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
