#!/bin/bash

SCRIPT_REPO="https://downloads.sourceforge.net/project/giflib/giflib-5.2.2.tar.gz"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    echo "download_file \"$SCRIPT_REPO\" \"giflib.tar.gz\""
    echo "tar -xof giflib.tar.gz --strip-components=1 || (echo 'Tar failed' && return 1)"
}

ffbuild_dockerbuild() {
    # Принудительно используем кросс-инструменты
    sed -i "s|^CC      =.*|CC      = $CC|" Makefile
    sed -i "s|^AR      =.*|AR      = $AR|" Makefile
    sed -i "s|^RANLIB  =.*|RANLIB  = $RANLIB|" Makefile

    make -j$(nproc) $MAKE_V libgif.a

    # Ручная установка, так как штатный install хочет в /usr/local
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX"/{include,lib,lib/pkgconfig}
    cp gif_lib.h "$FFBUILD_DESTDIR$FFBUILD_PREFIX/include/"
    cp libgif.a "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/"

    # Генерируем pkg-config файл вручную
    cat <<EOF > "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/giflib.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: giflib
Description: Library for reading and writing GIF files
Version: 5.2.2
Libs: -L\${libdir} -lgif
Cflags: -I\${includedir}
EOF
}

ffbuild_configure() {
    return 0
}
