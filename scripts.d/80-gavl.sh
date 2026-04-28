#!/bin/bash

SCRIPT_REPO="https://github.com/bplaum/gavl.git"
SCRIPT_COMMIT="f798ff76f6a4252f92cd209a1c973126e9673691"

ffbuild_depends() {
    echo gmp
    echo gnutls
    echo nettle
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    # исправляем фатальные ошибки configure.ac
    sed -i 's/AC_MSG_ERROR("getaddrinfo_a not found in libanl")/echo "Skipping libanl for Windows"/g' configure.ac
    sed -i 's/PKG_CHECK_MODULES(DRM, libdrm, have_drm="true")/PKG_CHECK_MODULES(DRM, libdrm, have_drm="true", have_drm="false")/g' configure.ac
    sed -i 's/LIBGAVL_LIBS="-lrt"/LIBGAVL_LIBS=""/g' configure.ac

    # исправляем фатальные ошибки check_funcs.m4
    sed -i 's/AC_MSG_ERROR(\[OpenGL not found\])/have_GL="false"/g' m4/check_funcs.m4
    sed -i 's/AC_MSG_ERROR(\[EGL not found\])/have_EGL="false"/g' m4/check_funcs.m4

    # запрещаем лезть в папки хоста
    find . -name "configure" -exec sed -i 's|-I/usr/include||g' {} + || true
    find . -name "Makefile.in" -exec sed -i 's|-I/usr/include||g' {} + || true

    # Исправляем архитектуру
    sed -i "s/-march=native -mtune=native/-march=${CPU_ARCH} -mtune=${CPU_TUNE}/g" m4/lqt_opt_cflags.m4

    ./autogen.sh

    export PKG_CONFIG_PATH="$FFBUILD_PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH"

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

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1
}
