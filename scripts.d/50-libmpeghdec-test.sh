#!/bin/bash

SCRIPT_REPO="https://github.com/Fraunhofer-IIS/mpeghdec.git"
SCRIPT_COMMIT="335a2587fed4d769f8a21ae8816afd0aaa226b4f"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    mkdir build_win && cd build_win

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake \
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DBUILD_SHARED_LIBS=OFF \
        -DENABLE_EXAMPLES=OFF \
        -DENABLE_DOC=OFF .. || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1
    
    # MPEG-H часто не генерирует .pc файл. Проверим и создадим, если нужно
    if [[ ! -f "$PC_DIR/mpeghdec.pc" ]]; then
        mkdir -p "$PC_DIR"
        cat <<EOF > "$PC_DIR/mpeghdec.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: mpeghdec
Description: MPEG-H 3D Audio Decoder library
Version: 1.0.0
Libs: -L\${libdir} -lmpeghdec
Libs.private: -lstdc++
Cflags: -I\${includedir}
EOF
    fi

}

ffbuild_configure() {
    echo --enable-libmpeghdec
}

ffbuild_unconfigure() {
    echo --disable-libmpeghdec
}
