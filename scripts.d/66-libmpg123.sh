#!/bin/bash

SCRIPT_REPO="https://github.com/madebr/mpg123.git"
SCRIPT_COMMIT="200dfc97bd263d6da1a5b1dad8a9dccc91e78932"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    rm -rf autom4te.cache config.cache
    mkdir -p m4
    libtoolize --force --copy
    aclocal -I m4 -I /usr/share/aclocal
    autoheader
    automake --add-missing --copy --force-missing
    autoconf

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-programs    # Нам не нужны mpg123.exe и прочие утилиты
        --disable-components  # Выключает дефолтное "собирать всё"
        --enable-libmpg123    # Собираем только саму библиотеку декодирования
        --disable-libout123   # Библиотека вывода звука
        --disable-libsyn123   # Библиотека синтеза/ресемплинга
        --with-cpu=x86-64
        --with-optimization=3
        --with-audio=dummy    # Отключаем системные аудио-движки (Win32/WASAPI)
        --disable-debug       # Убираем отладочный мусор
        --with-seektable=1000 # Стандартный размер таблицы поиска
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    # may need ${NOLTO}, так как mpg123 плохо дружит с LTO в ассемблере
    CFLAGS="$CFLAGS ${USELTO}${USELTO_C}" \
    CPPFLAGS="$CPPFLAGS" \
    LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}" || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    if [[ ! -f "${PC_DIR}/libmpg123.pc" ]]; then
        mkdir -p "${PC_DIR}"
        cat <<EOF > "${PC_DIR}/libmpg123.pc"
prefix=${FFBUILD_PREFIX}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libmpg123
Description: Fast console MPEG Audio Player and decoder library
Version: ${VER_FULL}
Libs: -L\${libdir} -lmpg123
Cflags: -I\${includedir}
EOF
    fi

    # symlink for openmpt
    ln -sf "$PC_DIR/libmpg123.pc" "$PC_DIR/mpg123.pc"
}
