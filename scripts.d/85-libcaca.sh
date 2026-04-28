#!/bin/bash

SCRIPT_REPO="https://github.com/cacalabs/libcaca.git"
SCRIPT_COMMIT="69a42132350da166a98afe4ab36d89008197b5f2"

ffbuild_depends() {
    echo freeglut
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    ./bootstrap

    # Отключаем попытку собрать плагины, которые требуют нативного X11/GL во время кросс-компиляции
    export ac_cv_header_x11_xlib_h=no
    # export ac_cv_header_gl_gl_h=no

    # Исправляем жестко зашитые имена либ в configure для MinGW
    sed -i 's/-lGL -lGLU/-lopengl32 -lglu32/g' configure

    # Устраняем конфликты безопасных строковых функций с MinGW
    # Мы переименовываем ВСЕ внутренние реализации libcaca, чтобы они не мешали системным
    log_info "Renaming conflicting safe string functions in libcaca source..."
    find . -type f -name "*.c" -exec sed -i 's/\bsprintf_s\b/caca_sprintf_s/g' {} +
    find . -type f -name "*.c" -exec sed -i 's/\bvsnprintf_s\b/caca_vsnprintf_s/g' {} +
    sed -i 's/defined __KERNEL__/1/' caca/caca_types.h

    # Чтобы не тратить время на ошибки в тестах, мы просто обнуляем Makefile в папке с тестами
    echo "all:" > caca/t/Makefile.am
    echo "install:" >> caca/t/Makefile.am

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-doc
        --disable-csharp
        --disable-java
        --disable-python
        --disable-ruby
        --disable-imlib2
        --enable-gl
        --disable-ncurses
        --disable-slang
        --disable-conio
    )

    if [[ $TARGET == linux64 ]]; then
        myconf+=(
        --enable-x11
        )
    elif [[ $TARGET == win* ]]; then
        myconf+=(
        --disable-x11
        --enable-win32
        )
    fi

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    local GL_LIBS="-lglut -lglu32 -lopengl32 -lgdi32 -lwinmm"
    local GL_CFLAGS=""
    [[ "${PREFER_SHARED}" != "1" ]] && GL_CFLAGS="-DFREEGLUT_STATIC"

    CC="${FFBUILD_CROSS_PREFIX}gcc" \
    CXX="${FFBUILD_CROSS_PREFIX}g++" \
    CFLAGS="$CFLAGS -Wno-implicit-function-declaration $GL_CFLAGS ${USELTO}" \
    CPPFLAGS="$CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS -Wno-implicit-function-declaration $GL_CFLAGS ${USELTO}" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    LIBS="$LIBS $GL_LIBS" \
    ./configure "${myconf[@]}" || return 1

    # Сборка только библиотеки
    # Мы явно просим собрать папку caca, а не всё дерево с тестами
    make -C caca -j$(nproc) $MAKE_V || return 1

    # Установка вручную, чтобы не заходить в папку 't'
    make -C caca install DESTDIR="$FFBUILD_DESTDIR" || return 1

    # Установка заголовочных файлов из корня (они нужны FFmpeg)
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include"
    cp caca/caca.h caca/caca0.h caca/caca_conio.h caca/caca_types.h "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include/"

    # libcaca иногда кладет .pc файл в странные места или пишет туда мусор
    local PC_FILE="$PC_DIR/caca.pc"
    if [[ -f "$PC_FILE" ]]; then
        sed -i "s|^prefix=.*|prefix=$FFBUILD_PREFIX|" "$PC_FILE"
        # FFmpeg требует явного указания системных либ для статики
        sed -i '/^Libs.private:/ s/$/ -lgdi32/' "$PC_FILE"
    fi
}

ffbuild_configure() {
    echo --enable-libcaca
}

ffbuild_unconfigure() {
    echo --disable-libcaca
}
