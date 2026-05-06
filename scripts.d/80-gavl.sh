#!/bin/bash

SCRIPT_REPO="https://github.com/bplaum/gavl.git"
SCRIPT_COMMIT="f798ff76f6a4252f92cd209a1c973126e9673691"

ffbuild_depends() {
    echo gmp
    echo gnutls
    echo nettle
    echo iconv
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    # исправляем фатальные ошибки
    sed -i 's/AC_MSG_ERROR("getaddrinfo_a not found in libanl")/echo "Skipping libanl"/g' configure.ac
    sed -i 's/PKG_CHECK_MODULES(DRM, libdrm, have_drm="true")/have_drm="false"; DRM_CFLAGS=""; DRM_LIBS=""/g' configure.ac
    sed -i 's/LIBGAVL_LIBS="-lrt"/LIBGAVL_LIBS=""/g' configure.ac
    sed -i 's/AC_MSG_ERROR(\[OpenGL not found\])/have_GL="false"/g' m4/check_funcs.m4
    sed -i 's/AC_MSG_ERROR(\[EGL not found\])/have_EGL="false"/g' m4/check_funcs.m4
    sed -i "s/-march=native -mtune=native//g" m4/lqt_opt_cflags.m4
    find . -name "Makefile.am" -exec sed -i 's/@DRM_CFLAGS@//g' {} + || true
    # Фикс qsort_r для MinGW
    log_info "Neutralizing gavl_array_sort to avoid qsort_r issues on Windows..."
    sed -i 's/qsort_r(/ \/\/ qsort_r(/g' gavl/array.c

    log_info "Neutralizing problematic C files..."
    SYSTEM_FILES=(
        hw.c hw_dmabuf.c hw_memfd.c 
        http.c httpclient.c sap.c urlvars.c 
        network.c socket.c socketaddress.c 
        compression.c io_fd.c io_socket.c io_stdio.c io_tls.c io_cipher.c 
        log.c metadata.c reftable.c 
        timer.c threadpool.c
        time.c utils.c
    )

    for f in "${SYSTEM_FILES[@]}"; do
        if [ -f "gavl/$f" ]; then
            echo "/* Disabled for Windows */" > "gavl/$f"
        fi
    done

    # touch include/iconv.h

    ./autogen.sh

    cat <<EOF > gavl_fix.h
#ifndef GAVL_WIN_FIX_H
#define GAVL_WIN_FIX_H

#define R_OK 4
#define W_OK 2
#define X_OK 1
#define F_OK 0
static inline int access(const char *path, int mode) { return 0; }

#define HAVE_FTRUNCATE 1
#define _UNISTD_H_ 
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
EOF

    # Склеиваем основные заголовки
    cat include/gavl/gavl_version.h.in \
        include/gavl/gavl_types.h \
        include/gavl/gavl.h >> gavl_fix.h

    sed -i '/#include <gavl\/gavl.h>/d; /#include <gavl\/gavl_types.h>/d; /#include <gavl\/gavl_version.h>/d' gavl_fix.h
    echo "#endif" >> gavl_fix.h

    sed -i 's/off_t ftruncate/#define ftruncate_skipped/g' include/gavl/io.h

    find . -type f \( -name "Makefile.in" -o -name "configure" \) -exec \
        sed -i "s|-I/usr/include|-I\$(top_srcdir)/include|g" {} + || true

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --with-pic
        --without-doxygen
        # если будут ошибки ассемблера
        # --disable-simd
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    CFLAGS="$CFLAGS ${USELTO}${USELTO_C} -Wno-implicit-function-declaration" \
    CPPFLAGS="$CPPFLAGS -I$(pwd)/include -I$(pwd)/include/gavl" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" \
        ac_cv_func_getaddrinfo_a=no \
        ac_cv_func_memalign=no \
        ac_cv_func_posix_memalign=no \
        ac_cv_func_ftruncate=yes \
        have_GL=no \
        have_EGL=no \
        ac_cv_header_sys_times_h=no || return 1

    make -C gavl -j$(nproc) $MAKE_V \
        CFLAGS="$CFLAGS ${USELTO}${USELTO_C} -I$(pwd) -include $(pwd)/gavl_fix.h" \
        LDFLAGS="$LDFLAGS ${USELTO}" || return 1
    make -C gavl install DESTDIR="$FFBUILD_DESTDIR" || return 1

    mkdir -p "$INSTALL_ROOT/include/gavl" "$PC_DIR"
    cp include/gavl/*.h "$INSTALL_ROOT/include/gavl/"

    local PC_FILE="$PC_DIR/gavl.pc"
    if [[ -f "gavl.pc" ]]; then
        cp gavl.pc "$PC_DIR"
        sed -i "s|^prefix=.*|prefix=$FFBUILD_PREFIX|" "$PC_FILE"
        sed -i 's/Libs.private:/Libs.private: -lnettle -lhogweed -lgnutls -liconv/' "$PC_FILE"
    fi
}
