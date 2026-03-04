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
    apply_patches

    mkdir build_win && cd build_win

    # Используем стандартный CMAKE_TOOLCHAIN_FILE из вашего окружения
    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DBUILD_SHARED_LIBS=OFF \
        -DENABLE_EXAMPLES=OFF \
        -DENABLE_DOC=OFF \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        ..

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"
    
    # MPEG-H часто не генерирует .pc файл. Проверим и создадим, если нужно
    if [[ ! -f "$FFBUILD_DESTPREFIX/lib/pkgconfig/mpeghdec.pc" ]]; then
        mkdir -p "$FFBUILD_DESTPREFIX/lib/pkgconfig"
        cat <<EOF > "$FFBUILD_DESTPREFIX/lib/pkgconfig/mpeghdec.pc"
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

    get_deps_list
}

ffbuild_configure() {
    echo --enable-libmpeghdec
}

ffbuild_unconfigure() {
    echo --disable-libmpeghdec
}
