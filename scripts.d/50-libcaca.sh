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
    if [[ -d "/builder/patches/libcaca" ]]; then
        for patch in /builder/patches/libcaca/*.patch; do
            log_info "APPLYING PATCH: $patch"
            if patch -p1 -N -r - < "$patch"; then
                log_info "${GREEN}${CHECK_MARK} SUCCESS: Patch applied.${NC}"
            else
                log_error "${RED}${CROSS_MARK} ERROR: PATCH FAILED! ${CROSS_MARK}${NC}"
                # return 1 # если нужно прервать сборку при ошибке
            fi
        done
    fi

    # Исправляем конфликты типов для MinGW
    # libcaca часто переопределяет то, что уже есть в Windows заголовках
    sed -i 's/defined __KERNEL__/1/' caca/caca_types.h

    ./bootstrap

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-shared
        --enable-static
        --disable-doc
        --disable-cpp
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

    # Конфигурация с подавлением ошибок путей
    ./configure "${myconf[@]}" CFLAGS="$CFLAGS -D_WIN32" LDFLAGS="$LDFLAGS"

    # Сборка
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

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
