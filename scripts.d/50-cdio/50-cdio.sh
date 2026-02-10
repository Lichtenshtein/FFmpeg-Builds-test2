#!/bin/bash

SCRIPT_REPO="https://github.com/rocky/libcdio-paranoia.git"
SCRIPT_COMMIT="53718dbe36ee9fd42e97527188a788f2754288c0"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    # Иногда старые версии m4 мешают, очистим
    find . -name "config.cache" -delete

    autoreconf -if

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
    echo "--- Running Make ---"
    make -j$(nproc) V=1
    echo "--- Running Make Install ---"
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-libcdio
}

ffbuild_unconfigure() {
    echo --disable-libcdio
}
