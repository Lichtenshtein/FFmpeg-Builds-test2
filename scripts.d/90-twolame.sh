#!/bin/bash

SCRIPT_REPO="https://github.com/njh/twolame.git"
SCRIPT_COMMIT="3c7d49d95be71c26afdbaef14def92f3460c7373"

export SKIP_CONF_FINDER=1

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    # libtoolize version detection is broken, disable it, we got the right versions
    printf 'print "999999\\n"\n' > autogen-get-version-mock.pl
    sed -i -e 's|/autogen-get-version.pl|/autogen-get-version-mock.pl|g' ./autogen.sh

    # Используем NOCONFIGURE, чтобы запустить configure вручную с нашими флагами
    NOCONFIGURE=1 ./autogen.sh

    # Заглушка для man-страниц, чтобы не требовать help2man
    mkdir -p doc
    touch doc/twolame.1

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --with-pic
        --disable-shared
        --enable-static
        --disable-sndfile
        --disable-maintainer-mode
    )

    CFLAGS="$CFLAGS" \
    LDFLAGS="$LDFLAGS" \
    CPPFLAGS="$CPPFLAGS -DLIBTWOLAME_STATIC" \
    CXXFLAGS="$CXXFLAGS -DLIBTWOLAME_STATIC" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    local PC_FILE="$PC_DIR/twolame.pc"
    if [[ -f "$PC_FILE" ]]; then
        # Исправляем префикс, если он стал абсолютным
        sed -i "s|^prefix=.*|prefix=$FFBUILD_PREFIX|" "$PC_FILE"
        # Добавляем флаг статики в Cflags
        if ! grep -q "LIBTWOLAME_STATIC" "$PC_FILE"; then
            sed -i 's/Cflags:/Cflags: -DLIBTWOLAME_STATIC /' "$PC_FILE"
        fi
        # Добавляем математическую библиотеку для статической линковки
        echo "Libs.private: -lm" >> "$PC_FILE"
    fi

}

ffbuild_configure() {
    echo --enable-libtwolame
}

ffbuild_unconfigure() {
    echo --disable-libtwolame
}

ffbuild_cppflags() {
    echo "-DLIBTWOLAME_STATIC"
}
