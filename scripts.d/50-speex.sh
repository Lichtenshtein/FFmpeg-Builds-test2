#!/bin/bash

SCRIPT_REPO="https://github.com/xiph/speex.git"
SCRIPT_COMMIT="05895229896dc942d453446eba6f9f5ddcf95422"

ffbuild_enabled() {
    [[ $TARGET == *arm64 ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    autoreconf -i

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-shared
        --enable-static
        --with-pic
        --disable-binaries
        --enable-sse
    )

    # Конфигурация. Добавляем CFLAGS для стабильности плавающей точки
    ./configure "${myconf[@]}" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"

    # Сборка
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # ФИКС pkg-config (Критично для FFmpeg)
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/speex.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i "s|^prefix=.*|prefix=$FFBUILD_PREFIX|" "$PC_FILE"
        # Добавляем математическую либу для статики
        echo "Libs.private: -lm" >> "$PC_FILE"
    fi
}

ffbuild_configure() {
    echo --enable-libspeex
}

ffbuild_unconfigure() {
    echo --disable-libspeex
}
