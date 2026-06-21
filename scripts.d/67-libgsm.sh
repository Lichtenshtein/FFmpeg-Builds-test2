#!/bin/bash
export USE_VERS_FINDER=1
SCRIPT_REPO="https://github.com/MartinEesmaa/libgsm.git"
SCRIPT_COMMIT="0f915c8872786fed91bb67837e3ad0c7a7144c1e"

# SCRIPT_REPO="https://github.com/maekawa-mugi/libgsm-playground.git"
# SCRIPT_COMMIT="f7fed756ba3c28792b876236cfbc69524ca048c7"

export SKIP_PRE_PATCH=1

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
    export INSTALL_ROOT="$INSTALL_ROOT"
    export CC="${FFBUILD_TOOLCHAIN}-gcc"

    make libgsm -j$(nproc) $MAKE_V || return 1
    
    mkdir -p "$INSTALL_ROOT/include/gsm"
    mkdir -p "$INSTALL_ROOT/lib"
    cp lib/libgsm.a "$INSTALL_ROOT/lib/"
    cp include/gsm/*.h "$INSTALL_ROOT/include/gsm"
    cp include/gsm/gsm.h "$INSTALL_ROOT/include/"

    mkdir -p "${PC_DIR}"
    cat <<EOF > "${PC_DIR}/gsm.pc"
prefix=${FFBUILD_PREFIX}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: GSM
Description: GSM 06.10 lossy speech compression library used in Mobile telecommunication (GSM)
Version: ${VER_FULL}
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
