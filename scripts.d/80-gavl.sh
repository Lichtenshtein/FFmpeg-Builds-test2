#!/bin/bash

SCRIPT_REPO="https://github.com/bplaum/gavl.git"
SCRIPT_COMMIT="f798ff76f6a4252f92cd209a1c973126e9673691"

ffbuild_depends() {
    echo gmp
    echo gnutls
    echo nettle
    echo libiconv
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

# let's create our own Frankenstein monster

if [[ $TARGET == win64 ]]; then

    log_info "Creating stubs for missing gavl functions..."
    cat <<EOF > gavl/gavl_stubs.c
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

// Подключаем типы gavl, чтобы сигнатуры совпали
typedef struct gavl_thread_pool_s gavl_thread_pool_t;

// Логи и отладка
void gavl_log_translate(int l) {}
void gavl_dprintf(const char *format, ...) {}
void gavl_diprintf(int indent, const char *format, ...) {}
void gavl_hexdump(const uint8_t * d, int len, int max_len) {}
void gavl_hexdumpi(int indent, const uint8_t * d, int len, int max_len) {}

// Строковые утилиты
char * gavl_strdup(const char * s) { return s ? strdup(s) : NULL; }
char * gavl_strtrim(char * s) { return s; }
char ** gavl_strbreak(const char * s, const char * delim) { return NULL; }
void gavl_strbreak_free(char ** s) {}
int gavl_sprintf(char *str, const char *format, ...) { return 0; }

// Hardware / HW
void gavl_hw_destroy_video_frame(void *f) {}
void gavl_hw_destroy_packet(void *p) {}
int gavl_hw_ctx_get_type(void *c) { return 0; }
const char * gavl_hw_type_to_string(int t) { return "none"; }

// Thread Pool (Исправлено под лог ошибки)
int gavl_thread_pool_get_num_threads(gavl_thread_pool_t *p) { return 1; }

void gavl_thread_pool_run(void (*func)(void*, int, int), void *arg, 
                          int start, int len, void * pool, int threads) {
    if (func) func(arg, start, len);
}

void gavl_thread_pool_stop(void * client_data, int thread) {}

// Time / Benchmark (Исправлено под лог ошибки)
int64_t gavl_time_unscale(int scale, int64_t t) { return t; }
uint64_t gavl_benchmark_get_time(int flags) { return 0; }
EOF

    # Добавляем файл в список сборки Makefile.am вручную
    sed -i 's/libgavl_la_SOURCES = /libgavl_la_SOURCES = gavl_stubs.c /' gavl/Makefile.am

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
            echo "/* Disabled */" > "gavl/$f"
        fi
    done

fi

    ./autogen.sh

if [[ $TARGET == win64 ]]; then

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

fi

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

if [[ $TARGET == win64 ]]; then

    CFLAGS="$CFLAGS ${NOLTO} -Wno-implicit-function-declaration" \
    CPPFLAGS="$CPPFLAGS -I$(pwd)/include -I$(pwd)/include/gavl" \
    LDFLAGS="$LDFLAGS ${NOLTO}" \
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
        CFLAGS="$CFLAGS ${NOLTO} -I$(pwd) -include $(pwd)/gavl_fix.h" \
        LDFLAGS="$LDFLAGS ${NOLTO}" || return 1

elif [[ $TARGET == linux64 ]]; then

    CFLAGS="$CFLAGS ${USELTO}${USELTO_C} -Wno-implicit-function-declaration" \
    CPPFLAGS="$CPPFLAGS" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_C}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -C gavl -j$(nproc) $MAKE_V \
        CFLAGS="$CFLAGS ${USELTO}${USELTO_C}" \
        LDFLAGS="$LDFLAGS ${USELTO}" || return 1

fi

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
