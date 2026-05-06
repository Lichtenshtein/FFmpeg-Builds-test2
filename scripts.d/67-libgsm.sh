#!/bin/bash

SCRIPT_REPO="https://github.com/MartinEesmaa/libgsm.git"
SCRIPT_COMMIT="0f915c8872786fed91bb67837e3ad0c7a7144c1e"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    export CFLAGS="$CFLAGS -DNeedFunctionPrototypes=1 -c -DSASR -DWAV49 -Wno-comment ${USELTO}${USELTO_C}"
    export CCFLAGS="$CFLAGS -DNeedFunctionPrototypes=1 -c -DSASR -DWAV49 -Wno-comment ${USELTO}${USELTO_C}"
    export LDFLAGS="$LDFLAGS ${USELTO}"
    export CPPFLAGS="$CPPFLAGS"
    export CXXFLAGS="$CXXFLAGS ${USELTO}${USELTO_C}"
    export INSTALL_ROOT="$FFBUILD_DESTPREFIX"
    export CC="${FFBUILD_TOOLCHAIN}-gcc"

    make libgsm -j$(nproc) $MAKE_V || return 1
    
    mkdir -p "$FFBUILD_DESTPREFIX/include/gsm"
    mkdir -p "$FFBUILD_DESTPREFIX/lib"
    cp lib/libgsm.a "$FFBUILD_DESTPREFIX/lib/"
    cp include/gsm/*.h "$FFBUILD_DESTPREFIX/include/gsm"
    cp include/gsm/gsm.h "$FFBUILD_DESTPREFIX/include/"

    mkdir -p "${PC_DIR}"
    cat <<EOF > "${PC_DIR}/gsm.pc"
prefix=${FFBUILD_PREFIX}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: gsm
Description: GSM 06.10 lossy speech compression library
Version: 1.0.13
Libs: -L\${libdir} -lgsm
Cflags: -I\${includedir} -I\${includedir}/gsm
EOF
}

ffbuild_configure() {
    echo --enable-libgsm
}

ffbuild_unconfigure() {
    echo --disable-libgsm
}
