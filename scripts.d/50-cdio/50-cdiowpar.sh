#!/bin/bash

SCRIPT_REPO="https://github.com/rocky/libcdio-paranoia.git"
SCRIPT_COMMIT="53718dbe36ee9fd42e97527188a788f2754288c0"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    autoreconf -if

    # POSIX_C_SOURCE открывает clock_gettime в time.h MinGW
    # -include time.h гарантирует, что заголовок будет прочитан первым
    export CFLAGS="$CFLAGS -D_POSIX_C_SOURCE=199309L -include time.h -include pthread.h"
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

    ./configure "${myconf[@]}"

    # Если вдруг configure сбросит CFLAGS, применим sed как "план Б" для конкретного файла
    sed -i '1i#define _POSIX_C_SOURCE 199309L\n#include <time.h>\n#include <pthread.h>' lib/cdda_interface/utils.c

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR" $MAKE_V
}

ffbuild_configure() {
    echo --enable-libcdio
}

ffbuild_unconfigure() {
    echo --disable-libcdio
}
