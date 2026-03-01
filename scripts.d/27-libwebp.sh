#!/bin/bash

SCRIPT_REPO="https://github.com/webmproject/libwebp.git"
SCRIPT_COMMIT="f342dfc1756785df8803d25478bf664c0de629de"

ffbuild_depends() {
    echo libpng
    echo libjpeg-turbo
    echo libtiff
    echo giflib
    echo zlib
    echo zstd
    echo xz
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    ./autogen.sh

    # Помогаем Autotools найти статические либы в нашем префиксе
    export LDFLAGS="$LDFLAGS -L$FFBUILD_PREFIX/lib -llzma"
    export CPPFLAGS="$CPPFLAGS -I$FFBUILD_PREFIX/include"

    # передаем зависимости libtiff, чтобы тесты линковки не падали
    export LIBS="-ltiff -ljpeg -llzma -lzstd -ljbig -lpng16 -lz -lm"

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-shared
        --enable-static
        --with-pic
        --enable-everything
        --disable-gl
        --disable-sdl
    )

    # Добавляем LTO если включено
    [[ "$USE_LTO" == "1" ]] && export CFLAGS="$CFLAGS -flto" && export LDFLAGS="$LDFLAGS -flto"

    ./configure "${myconf[@]}"
    # Исправляем возможную ошибку в Makefile, где линковка примеров может игнорировать LIBS
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # --- Блок автоматической отладки зависимостей ---
    log_debug "[DEBUG] Dependencies for $STAGENAME: ${0##*/}"
    # Показываем все сгенерированные .pc файлы и их зависимости
    find "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig" -name "*.pc" -exec echo "--- {} ---" \; -exec cat {} \;
    # Показываем внешние символы (Undefined) для каждой собранной .a библиотеки
    # фильтруем только те символы, которые реально ведут к другим библиотекам
    find "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib" -name "*.a" -print0 | xargs -0 -I{} sh -c "
        echo '--- Symbols in {} ---';
        ${FFBUILD_TOOLCHAIN}-nm {} | grep ' U ' | awk '{print \$2}' | sort -u | head -n 20
    "
}

ffbuild_configure() {
    echo --enable-libwebp
}

ffbuild_unconfigure() {
    echo --disable-libwebp
}
