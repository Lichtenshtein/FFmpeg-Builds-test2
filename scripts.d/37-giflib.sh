#!/bin/bash

SCRIPT_REPO="https://github.com/arthenica/giflib.git"
SCRIPT_COMMIT="edff4aed17f857442ab0cac31566572ba08f93d3"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    # Принудительно используем кросс-инструменты
    sed -i "s|^CC      =.*|CC      = $CC|" Makefile
    sed -i "s|^AR      =.*|AR      = $AR|" Makefile
    sed -i "s|^RANLIB  =.*|RANLIB  = $RANLIB|" Makefile

    make \
      CFLAGS="$CFLAGS ${USELTO}${USELTO_C}" \
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
Version: ${VER_FULL}
Libs: -L\${libdir} -lgif
Cflags: -I\${includedir}
EOF
}
