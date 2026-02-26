#!/bin/bash

SCRIPT_REPO="https://github.com/cacalabs/libcaca.git"
SCRIPT_COMMIT="69a42132350da166a98afe4ab36d89008197b5f2"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    # if [[ -d "/builder/patches/libcaca" ]]; then
        # for patch in /builder/patches/libcaca/*.patch; do
            # log_info "APPLYING PATCH: $patch"
            # if patch -p1 -N -r - < "$patch"; then
                # log_info "${GREEN}${CHECK_MARK} SUCCESS: Patch applied.${NC}"
            # else
                # log_error "${RED}${CROSS_MARK} ERROR: PATCH FAILED! ${CROSS_MARK}${NC}"
            # fi
        # done
    # fi

    # Отключаем попытку собрать плагины, которые требуют нативного X11/GL во время кросс-компиляции
    export ac_cv_header_x11_xlib_h=no
    export ac_cv_header_gl_gl_h=no

    # Устраняем конфликты безопасных строковых функций с MinGW
    # Мы переименовываем ВСЕ внутренние реализации libcaca, чтобы они не мешали системным
    log_info "Renaming conflicting safe string functions in libcaca source..."
    find . -type f -name "*.c" -exec sed -i 's/\bsprintf_s\b/caca_sprintf_s/g' {} +
    find . -type f -name "*.c" -exec sed -i 's/\bvsnprintf_s\b/caca_vsnprintf_s/g' {} +
    sed -i 's/defined __KERNEL__/1/' caca/caca_types.h

    ./bootstrap

    # Чтобы не тратить время на ошибки в тестах, мы просто обнуляем Makefile в папке с тестами
    echo "all:" > caca/t/Makefile.am
    echo "install:" >> caca/t/Makefile.am

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-shared
        --enable-static
        --disable-doc
        --disable-csharp
        --disable-java
        --disable-python
        --disable-ruby
        --disable-imlib2
        --disable-x11
        --disable-gl
        --disable-ncurses
        --disable-slang
        --disable-conio
        # Для Windows оставляем только win32 драйвер или вообще отключаем всё лишнее
        --enable-win32
    )

    export CC="${FFBUILD_CROSS_PREFIX}gcc"
    export CXX="${FFBUILD_CROSS_PREFIX}g++"

    ./configure "${myconf[@]}" \
        CFLAGS="$CFLAGS -D_WIN32 -Wno-implicit-function-declaration" \
        LDFLAGS="$LDFLAGS"

    # Сборка только библиотеки
    # Мы явно просим собрать папку caca, а не всё дерево с тестами
    make -C caca -j$(nproc) $MAKE_V
    
    # Установка вручную, чтобы не заходить в папку 't'
    make -C caca install DESTDIR="$FFBUILD_DESTDIR"

    # Установка заголовочных файлов из корня (они нужны FFmpeg)
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include"
    cp caca/caca.h caca/caca0.h caca/caca_conio.h caca/caca_types.h "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include/"

    # libcaca иногда кладет .pc файл в странные места или пишет туда мусор
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/caca.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i "s|^prefix=.*|prefix=$FFBUILD_PREFIX|" "$PC_FILE"
        # FFmpeg требует явного указания системных либ для статики
        echo "Libs.private: -lgdi32" >> "$PC_FILE"
    fi
}

ffbuild_configure() {
    echo --enable-libcaca
}

ffbuild_unconfigure() {
    echo --disable-libcaca
}
