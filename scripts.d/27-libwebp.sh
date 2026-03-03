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

    export CFLAGS="$CFLAGS -DWEBP_STATIC -D_WIN32"
    # Собираем список либ для тестов конфигурации
    local WEBP_LIBS="-ltiff -ljpeg -lpng16 -lzstd -llzma -ljbig -lz -lm -lws2_32 -lpthread"

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

    ./configure "${myconf[@]}" \
        LDFLAGS="$LDFLAGS -L$FFBUILD_PREFIX/lib" \
        CPPFLAGS="$CPPFLAGS -I$FFBUILD_PREFIX/include" \
        LIBS="$WEBP_LIBS"

    # Явно вызываем make и проверяем его успех
    make -j$(nproc) $MAKE_V 
    make install DESTDIR="$FFBUILD_DESTDIR"

    # libwebp генерирует несколько .pc файлов (libwebp, libwebpmux, libsharpyuv)
    # Нужно убедиться, что они содержат системные либы для Windows
    for pc in libwebp.pc libwebpmux.pc libsharpyuv.pc; do
        local PC_PATH="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/$pc"
        if [[ -f "$PC_PATH" ]]; then
            # Добавляем -lws2_32 (нужен для некоторых функций WebP в Windows)
            sed -i "/^Libs.private:/ s/$/ -lshlwapi -lws2_32 -lpthread/" "$PC_PATH"
        fi
    done

    # Вызываем отладку зависимостей
    get_deps_list
}

ffbuild_cppflags() {
    echo "-DWEBP_STATIC"
}

ffbuild_configure() {
    echo --enable-libwebp
}

ffbuild_unconfigure() {
    echo --disable-libwebp
}
