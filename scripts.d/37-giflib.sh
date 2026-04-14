#!/bin/bash

# SCRIPT_REPO="https://gh.msys2.org/repo/mingw/sources/mingw-w64-giflib-6.1.2.tar.gz"

SCRIPT_REPO="https://github.com/codacy-open-source-projects-scans/giflib.git"
SCRIPT_COMMIT="9bef00b547ef55f64d8fe66e38ca28aac8a72ad6"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    # echo "download_file \"$SCRIPT_REPO\" \"giflib.tar.gz\""
    # echo "tar -xof giflib.tar.gz --strip-components=1 || (echo 'Tar failed' && return 1)"
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    # Принудительно используем кросс-инструменты
    sed -i "s|^CC      =.*|CC      = $CC|" Makefile
    sed -i "s|^AR      =.*|AR      = $AR|" Makefile
    sed -i "s|^RANLIB  =.*|RANLIB  = $RANLIB|" Makefile

    make \
      CFLAGS="$CFLAGS ${USELTO}" \
      LDFLAGS="$LDFLAGS ${USELTO}" \
      -j$(nproc) $MAKE_V libgif.a || return 1

    # Ручная установка, так как штатный install хочет в /usr/local
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX"/{include,lib,lib/pkgconfig}
    cp gif_lib.h "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include/"
    cp libgif.a "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/"

    # Генерируем pkg-config файл вручную
    cat <<EOF > "$PC_DIR/giflib.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: giflib
Description: Library for reading and writing GIF files
Version: 6.1.2
Libs: -L\${libdir} -lgif
Cflags: -I\${includedir}
EOF
}
