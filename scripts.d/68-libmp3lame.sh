#!/bin/bash

SCRIPT_REPO="https://svn.code.sf.net/p/lame/svn/trunk/lame"
SCRIPT_REV="6531"

ffbuild_depends() {
    echo base
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
    # Принудительно чиним конфиг для современных систем
    sed -i 's/AC_PREREQ(2.69)/AC_PREREQ(2.71)/' configure.in || true
    
    # Исправляем баг в Makefile, который может пытаться собрать документацию
    sed -i 's/SUBDIRS = mpglib libmp3lame frontend include doc dev/SUBDIRS = mpglib libmp3lame include/' Makefile.am

    autoreconf -fi

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --enable-nasm
        --enable-expopt=full # or "norm"; Whether to enable experimental optimizations
        --disable-gtktest
        # --disable-decoder # Exclude mpg123 decoder
        --disable-frontend # Do not build the lame executable
        # --enable-mp3x # Build GTK frame analyzer
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    local FLAGS="-ffast-math -Wno-implicit-function-declaration -Wno-int-conversion -Wno-error=incompatible-pointer-typ"

    # GCC 14 требует более мягких проверок для старого кода LAME
    CFLAGS="$CFLAGS $FLAGS ${USELTO}" \
    CPPFLAGS="$CPPFLAGS -DNDEBUG -D_ALLOW_INTERNAL_OPTIONS" \
    CXXFLAGS="$CXXFLAGS $FLAGS ${USELTO}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1
}

ffbuild_configure() {
    echo --enable-libmp3lame
}

ffbuild_unconfigure() {
    echo --disable-libmp3lame
}
