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
    sed -i "s/-march=native -mtune=native/-march=${CPU_ARCH} -mtune=${CPU_TUNE}/g" m4/lqt_opt_cflags.m4
    find . -name "Makefile.am" -exec sed -i 's/@DRM_CFLAGS@//g' {} + || true
    # Фикс qsort_r для MinGW
    log_info "Neutralizing gavl_array_sort to avoid qsort_r issues on Windows..."
    sed -i 's/qsort_r(/ \/\/ qsort_r(/g' gavl/array.c

    log_info "Disabling Linux-only hardware modules..."
    sed -i 's/hw_dmabuf.lo//g' gavl/Makefile.am
    sed -i 's/hw.lo//g' gavl/Makefile.am
    echo "/* Not for Windows */" > gavl/hw.c
    echo "/* Not for Windows */" > gavl/hw_dmabuf.c
    sed -i '1i #include <gavl/gavl.h>' include/gavl/value.h
    sed -i '1i #include <gavl/gavl.h>' include/gavl/msg.h
    export ac_cv_func_ftruncate=yes

    ./autogen.sh

    # тотальная чистка от /usr/include во всех сгенерированных файлах
    log_info "Removing all references to /usr/include from generated files..."
    find . -type f \( -name "Makefile.am" -o -name "Makefile.in" -o -name "configure" \) -exec \
        sed -i "s|-I/usr/include|-I${FFBUILD_PREFIX}/include|g" {} + || true

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

    CFLAGS="$CFLAGS ${USELTO}" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS ${USELTO}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" \
        ac_cv_func_getaddrinfo_a=no \
        ac_cv_func_memalign=no \
        ac_cv_func_posix_memalign=no \
        have_GL=no \
        have_EGL=no \
        ac_cv_header_sys_times_h=no || return 1

    make -C gavl -j$(nproc) $MAKE_V || return 1
    make -C gavl install DESTDIR="$FFBUILD_DESTDIR" || return 1
}
