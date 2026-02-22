#!/bin/bash

SCRIPT_REPO="https://github.com/tukaani-project/xz.git"
SCRIPT_COMMIT="54147ad65af12d9e4f60a8ce59094a8a30ad5919"

ffbuild_depends() {
    echo base
    echo libiconv
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
}

ffbuild_dockerbuild() {
    # Удаляем старые вспомогательные файлы, чтобы libtoolize и autoconf пересоздали их
    rm -rf build-aux
    mkdir -p build-aux

    # В xz autogen.sh сам вызывает все нужные инструменты в правильном порядке
    # Мы пропускаем генерацию документации и переводов для скорости
    ./autogen.sh --no-po4a --no-doxygen

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --build=x86_64-pc-linux-gnu
        --disable-symbol-versions
        --disable-shared
        --enable-static
        --with-pic
        --disable-nls
        --disable-scripts
        --disable-doc
    )

    ./configure "${myconf[@]}"
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"
}

ffbuild_configure() {
    echo --enable-lzma
}

ffbuild_unconfigure() {
    echo --disable-lzma
}
