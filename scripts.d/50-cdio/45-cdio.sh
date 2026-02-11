#!/bin/bash

SCRIPT_REPO="https://git.savannah.gnu.org/git/libcdio.git"

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
        --disable-maintainer-mode
        --without-cd-drive
        --without-cd-info
        --without-cdda-player
        --without-cd-read
        --without-iso-info
        --without-iso-read
        --disable-cpp-progs
        --with-pic
    )

    ./configure "${myconf[@]}"

    # Подменяем MAKEINFO на true, чтобы пропустить генерацию документации
    # и очищаем переменную в Makefile
    sed -i 's/MAKEINFO = .*/MAKEINFO = true/g' Makefile
    sed -i 's/SUBDIRS = .*/SUBDIRS = include lib/g' Makefile

    make -j$(nproc) V=1

    # Устанавливаем только библиотеку и заголовки, игнорируя doc
    make -C include install DESTDIR="$FFBUILD_DESTDIR"
    make -C lib install DESTDIR="$FFBUILD_DESTDIR"
    
    # Вручную устанавливаем .pc файлы, так как мы пропустили корень
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig"
    cp *.pc "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/"
}
