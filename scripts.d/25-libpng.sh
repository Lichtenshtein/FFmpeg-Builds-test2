#!/bin/bash

SCRIPT_REPO="https://github.com/glennrp/libpng.git"
SCRIPT_COMMIT="c3e304954a9cfd154bc0dfbfea2b01cd61d6546d"

ffbuild_depends() {
    echo base
    echo zlib
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    ./autogen.sh

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-shared
        --enable-static
        --disable-tests
        --disable-tools
        --with-pic
    )

    # Добавляем LTO если включено
    if [[ "$USE_LTO" == "1" ]]; then
        export CFLAGS="$CFLAGS -flto"
        export LDFLAGS="$LDFLAGS -flto"
    fi

    # Гарантируем, что zlib будет найден
    export CPPFLAGS="$CPPFLAGS -I$FFBUILD_PREFIX/include"
    export LDFLAGS="$LDFLAGS -L$FFBUILD_PREFIX/lib"

    ./configure "${myconf[@]}"
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # Создаем стандартные симлинки для совместимости
    # Многие старые пакеты ищут libpng16.pc или libpng.pc
    cd "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig"
    ln -sf libpng16.pc libpng.pc
}
