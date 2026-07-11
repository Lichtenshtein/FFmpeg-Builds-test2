#!/bin/bash

SCRIPT_REPO="https://github.com/arthenica/giflib.git"
SCRIPT_COMMIT="a8e3114a81f0987a61d06a41c99fd7cc2d58232c"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    echo "rm -rf tests"
}

ffbuild_dockerbuild() {
    set -e

    sed -i "s|^CC      =.*|CC      = $CC|" Makefile
    sed -i "s|^AR      =.*|AR      = $AR|" Makefile
    sed -i "s|^RANLIB  =.*|RANLIB  = $RANLIB|" Makefile

    make \
      CFLAGS="$CFLAGS ${USELTO}${USELTO_C}" \
      LDFLAGS="$LDFLAGS ${USELTO}${USELTO_L}" \
      -j$(nproc) $MAKE_V libgif.a || return 1

    mkdir -p "$INSTALL_ROOT"/{include,lib,lib/pkgconfig}
    cp gif_lib.h "$INSTALL_ROOT/include/"
    cp libgif.a "$INSTALL_ROOT/lib/"

    cat <<EOF > "$PC_DIR/giflib.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: giflib
Description: Library for reading, writing, and manipulating GIF images
Version: ${VER_FULL}
Libs: -L\${libdir} -lgif
Cflags: -I\${includedir}
EOF
}
