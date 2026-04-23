#!/bin/bash

SCRIPT_REPO="https://github.com/madebr/mpg123.git"
SCRIPT_COMMIT="64972c017377bf8972d8d245bff8234a2032a3d2"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    autoreconf -fi

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --host="$FFBUILD_TOOLCHAIN"
        --disable-programs    # Нам не нужны mpg123.exe и прочие утилиты
        --enable-libmpg123    # Собираем только саму библиотеку декодирования
        --disable-libout123   # Библиотека вывода звука
        --disable-libsyn123   # Библиотека синтеза/ресемплинга
        --with-cpu=x86-64
        --with-optimization=3
        --with-audio=dummy    # Отключаем системные аудио-движки (Win32/WASAPI)
        --disable-debug       # Убираем отладочный мусор
        --enable-yasm         # Используем yasm для AVX оптимизаций
        --with-seektable=1000 # Стандартный размер таблицы поиска
    )

    [[ "${PREFER_SHARED}" == "1" ]] && \
        myconf+=( --disable-static --enable-shared ) || \
        myconf+=( --enable-static --disable-shared )

    CFLAGS="$CFLAGS ${USELTO}" \
    CPPFLAGS="$CPPFLAGS" \
    LDFLAGS="$LDFLAGS ${USELTO}" \
    LIBS="$LIBS" \
    ./configure "${myconf[@]}"

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    mkdir -p "${PC_DIR}"
    if [ -f "${FFBUILD_DESTPREFIX}/lib/pkgconfig/libmpg123.pc" ]; then
        cp "${FFBUILD_DESTPREFIX}/lib/pkgconfig/libmpg123.pc" "${PC_DIR}/"
    fi
}
