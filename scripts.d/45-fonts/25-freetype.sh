#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/freetype/freetype.git"
SCRIPT_COMMIT="23b6cd27ff19b70cbf98e058cd2cf0647d5284ff"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    # Клонируем и сразу выкачиваем подмодули (dlg), чтобы они попали в архив
    echo "git clone --filter=blob:none --depth=1 \"$SCRIPT_REPO\" . && git submodule update --init --recursive"
}

ffbuild_dockerbuild() {
    # Обманываем Freetype, создавая файл-метку, что подмодули уже есть
    # и предотвращаем вызов git в autogen.sh
    export NOCONFIGURE=1
    ./autogen.sh

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-shared
        --enable-static
        --with-pic
        --without-harfbuzz
        --without-png
        --without-zlib
        --without-bzip2
    )

    ./configure "${myconf[@]}"
    make -j$(nproc)
    make install DESTDIR="$FFBUILD_DESTDIR"
    
    # Копируем результат в префикс
    cp -r "$FFBUILD_DESTDIR$FFBUILD_PREFIX"/. "$FFBUILD_PREFIX"/
}

