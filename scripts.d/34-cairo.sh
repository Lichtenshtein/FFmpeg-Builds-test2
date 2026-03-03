#!/bin/bash
SCRIPT_REPO="https://gitlab.freedesktop.org/cairo/cairo.git"
SCRIPT_COMMIT="2a4589266388622f8c779721c8a4e090966fae79"

ffbuild_depends() {
    echo zlib
    echo glib2
    echo fontconfig
    echo freetype
    echo libpng
    echo pixman
    echo harfbuzz
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    export CFLAGS="$CFLAGS -DCAIRO_WIN32_STATIC_BUILD"
    export CPPFLAGS="$CPPFLAGS -DCAIRO_WIN32_STATIC_BUILD"
    export LDFLAGS="${LDFLAGS/-static-libstdc++/} -static"

    # Включаем dwrite и d2d1, так как они нужны для современных шрифтов
    local WIN_LIBS="-lgdi32 -lmsimg32 -ldwrite -ld2d1 -lwindowscodecs $LIBS"
    local INT_LIBS="-lintl -liconv"
    local DEP_LIBS=$(pkg-config --libs --static fontconfig freetype2 harfbuzz pixman-1 libpng zlib)

    meson setup build \
        --prefix="$FFBUILD_PREFIX" \
        --cross-file=/cross.meson \
        --buildtype=release \
        --default-library=static \
        --wrap-mode=nodownload \
        -Dfontconfig=enabled \
        -Dfreetype=enabled \
        -Dglib=enabled \
        -Dpng=enabled \
        -Dsymbol-lookup=disabled \
        -Dtee=enabled \
        -Dtests=disabled \
        -Dxcb=disabled \
        -Dxlib=disabled \
        -Dzlib=enabled \
        -Dc_link_args="$LDFLAGS $DEP_LIBS $INT_LIBS $WIN_LIBS" \
        -Dcpp_link_args="$LDFLAGS $DEP_LIBS $INT_LIBS $WIN_LIBS" \
        || (tail -n 100 build/meson-logs/meson-log.txt && return 1)

    ninja -C build -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja -C build install

    # для статической линковки Cairo в FFmpeg под Windows
    # Cairo часто забывает прописать системные зависимости в .pc файл
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/cairo.pc"
    if [[ -f "$PC_FILE" ]]; then
        # Добавляем все системные либы в Libs.private, чтобы они не мешали основной строке Libs
        # Но при этом были доступны при --static
        sed -i "/^Libs.private:/ s/$/ $WIN_LIBS/" "$PC_FILE"
        # Убеждаемся, что дефайн статики прописан в Cflags pc-файла
        sed -i "/^Cflags:/ s/$/ -DCAIRO_WIN32_STATIC_BUILD/" "$PC_FILE"
    fi

    # Вызываем отладку зависимостей
    get_deps_list
}

ffbuild_cppflags() {
    echo "-DCAIRO_WIN32_STATIC_BUILD"
}
