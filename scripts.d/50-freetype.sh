#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/freetype/freetype.git"
SCRIPT_COMMIT="28407bc8cd1a3da43df7b11c40bc5c24b9883ac6"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    # Изменить 'v1' на 'v2', чтобы сбросить кэш загрузки
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" . "
}


ffbuild_dockerbuild() {
    # инициализация подмодуля dlg
    mkdir -p subprojects/dlg
    if [[ ! -f "subprojects/dlg/include/dlg/dlg.h" ]]; then
        git clone --depth 1 https://github.com/nyorain/dlg.git subprojects/dlg
    fi

    # Обманываем Freetype, создавая файл-метку, что подмодули уже есть
    # и предотвращаем вызов git в autogen.sh
    # export NOCONFIGURE=1

    ./autogen.sh

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --build=x86_64-pc-linux-gnu
        CC_BUILD=gcc
        --disable-shared
        --enable-static
        --with-pic
    )

    ./configure "${myconf[@]}"
    make -j$(nproc)
    make install DESTDIR="$FFBUILD_DESTDIR"
    
    echo "Libs.private: -lharfbuzz" >> "$FFBUILD_DESTPREFIX"/lib/pkgconfig/freetype2.pc
}

ffbuild_configure() {
    echo --enable-libfreetype
}

ffbuild_unconfigure() {
    echo --disable-libfreetype
}
