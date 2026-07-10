#!/bin/bash
export USE_VERS_FINDER=1
SCRIPT_REPO="https://github.com/arthenica/giflib.git"
SCRIPT_COMMIT="a8e3114a81f0987a61d06a41c99fd7cc2d58232c"

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
      LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
      -j$(nproc) $MAKE_V libgif.a || return 1

    # Ручная установка, так как штатный install хочет в /usr/local
    mkdir -p "$INSTALL_ROOT"/{include,lib,lib/pkgconfig}
    cp gif_lib.h "$INSTALL_ROOT/include/"
    cp libgif.a "$INSTALL_ROOT/lib/"

    # Генерируем pkg-config файл вручную
    cat <<EOF > "$PC_DIR/giflib.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: giflib
Description: Library for reading, writing, and manipulating GIF image files
Version: ${VER_FULL}
Libs: -L\${libdir} -lgif
Cflags: -I\${includedir}
EOF
}
