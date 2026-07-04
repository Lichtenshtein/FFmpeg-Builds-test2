#!/bin/bash
export USE_VERS_FINDER=1
SCRIPT_REPO="https://github.com/dlbeer/quirc.git"
SCRIPT_COMMIT="927d680904dc95fdff4cd9d022eb374b438ff8f2"

ffbuild_enabled() {
    [[ $TARGET == winarm64 ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    # Явно передаем инструменты, чтобы quirc не собрался под хост (Linux)
    make libquirc.a $MAKE_V -j$(nproc) CC="${CC}" AR="${AR}" CFLAGS="$CFLAGS ${USELTO}${USELTO_C}" || return 1
    
    mkdir -p "$INSTALL_ROOT/lib/" "$INSTALL_ROOT/include/"

    cp libquirc.a "$INSTALL_ROOT/lib/"
    cp lib/quirc.h "$INSTALL_ROOT/include/"

    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/quirc.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: quirc
Description: QR decoder library, for extracting and decoding them from images
Version: ${VER_FULL}
Libs: -L\${libdir} -lquirc
Cflags: -I\${includedir}
EOF
}

ffbuild_configure() {
    echo --enable-libquirc
}

ffbuild_unconfigure() {
    echo --disable-libquirc
}

ffbuild_cflags() {
    return 0
}

ffbuild_ldflags() {
    return 0
}
