#!/bin/bash

SCRIPT_REPO="https://github.com/ittiam-systems/libmpeghe.git"
SCRIPT_COMMIT="603275bb7647cdf8db86dbdf2291495d8fdcfa7f"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    cd encoder

    # Компиляция объектов с поддержкой LTO (через $CFLAGS)
    for mpeghe in *.c; do
        "$CC" -Wall -Wsequence-point $CFLAGS ${USELTO}${USELTO_C} $CPPFLAGS -I. "$mpeghe" -c -o "${mpeghe%.c}.o"
    done

    # Создание статической библиотеки. 
    # Используем $AR для поддержки LTO
    "$AR" -rcs libia_mpegh.a *.o
    "$RANLIB" libia_mpegh.a

    # Установка бинарников и заголовков
    mkdir -p "$FFBUILD_DESTPREFIX"/lib
    mkdir -p "$FFBUILD_DESTPREFIX"/include/ia_mpegh
    cp libia_mpegh.a "$FFBUILD_DESTPREFIX"/lib
    cp *.h "$FFBUILD_DESTPREFIX"/include/ia_mpegh/

    mkdir -p "$FFBUILD_DESTPREFIX"/lib/pkgconfig
    cat << EOF > "$FFBUILD_DESTPREFIX"/lib/pkgconfig/ia_mpegh.pc
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include/ia_mpegh

Name: ia_mpegh
Description: Ittiam MPEG-H HE Audio Encoder library
Version: 1.0.0
Libs: -L\${libdir} -lia_mpegh
Libs.private: -lm
Cflags: -I\${includedir}
EOF

    # Очистка
    rm -f *.o libia_mpegh.a
}

ffbuild_configure() {
    echo --enable-ia_mpegh
}

ffbuild_unconfigure() {
    echo --disable-ia_mpegh
}

ffbuild_libs() {
    echo -lia_mpegh
}
