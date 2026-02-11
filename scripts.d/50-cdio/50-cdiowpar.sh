#!/bin/bash

SCRIPT_REPO="https://github.com/rocky/libcdio-paranoia.git"
SCRIPT_COMMIT="53718dbe36ee9fd42e97527188a788f2754288c0"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    autoreconf -if

    # Добавляем pthread в линковку, чтобы тесты в configure прошли успешно
    # Используем -include для принудительного включения pthread.h во все файлы
    # Это гарантирует наличие CLOCK_MONOTONIC и clock_gettime
    export CFLAGS="$CFLAGS -include pthread.h"
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

    # Вставляем pthread.h в сгенерированный config.h
    # Это решает проблему "CLOCK_MONOTONIC undeclared"
    # if [[ -f "config.h" ]]; then
        # sed -i '1i#include <pthread.h>' config.h
    # fi

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR" $MAKE_V
}

ffbuild_configure() {
    echo --enable-libcdio
}

ffbuild_unconfigure() {
    echo --disable-libcdio
}
