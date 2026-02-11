#!/bin/bash

SCRIPT_REPO="https://github.com/rocky/libcdio-paranoia.git"
SCRIPT_COMMIT="53718dbe36ee9fd42e97527188a788f2754288c0"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    autoreconf -if

    # Вставляем инклуды в начало КАЖДОГО .c файла в папке lib
    find lib -name "*.c" -exec sed -i '1i#define _POSIX_C_SOURCE 199309L\n#include <time.h>\n#include <pthread.h>' {} +

    export LIBS="$LIBS -lpthread"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-shared
        --enable-static
        --disable-example-progs
        --disable-maintainer-mode
        --enable-cpp-progs=no
        --with-pic
    )

    ./configure "${myconf[@]}" CFLAGS="$CFLAGS -D_POSIX_C_SOURCE=199309L"

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR" $MAKE_V
}

ffbuild_configure() {
    echo --enable-libcdio
}

ffbuild_unconfigure() {
    echo --disable-libcdio
}
