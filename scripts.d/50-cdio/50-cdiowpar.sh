#!/bin/bash

SCRIPT_REPO="https://github.com/rocky/libcdio-paranoia.git"
SCRIPT_COMMIT="53718dbe36ee9fd42e97527188a788f2754288c0"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    autoreconf -if

    # В MinGW clock_gettime находится в libwinpthread
    # добавляем -lpthread, чтобы линковщик нашел clock_gettime
    export LIBS="$LIBS -lpthread"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-shared
        --enable-static
        --disable-example-progs
        --disable-maintainer-mode
        --disable-test-progs
        --without-versioned-libs
        --with-pic
    )

    ./configure "${myconf[@]}"

    # Хак для исправления 'unknown type name clockid_t' под MinGW
    # Мы принудительно вставляем заголовок в сгенерированный конфиг
    if [ -f "config.h" ]; then
        echo "#include <pthread.h>" >> config.h
        echo "#define HAVE_CLOCK_GETTIME 1" >> config.h
    fi

    make -j$(nproc) V=1
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-libcdio
}

ffbuild_unconfigure() {
    echo --disable-libcdio
}
