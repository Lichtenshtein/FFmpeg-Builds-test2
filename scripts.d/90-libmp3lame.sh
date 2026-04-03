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
        --disable-shared
        --enable-static
        --enable-nasm
        --disable-gtktest
        --disable-frontend
    )

    # export CFLAGS="$CFLAGS -DNDEBUG -D_ALLOW_INTERNAL_OPTIONS -Wno-error=incompatible-pointer-types"
    # GCC 14 требует более мягких проверок для старого кода LAME

    CFLAGS="$CFLAGS -ffast-math -Wno-implicit-function-declaration -Wno-int-conversion -Wno-error=incompatible-pointer-types" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS" \
    LDFLAGS="$LDFLAGS" \
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
