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

    mkdir -p build && cd build

    local myconf=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DBUILD_SHARED_LIBS=$([ "${PREFER_SHARED}" == "1" ] && echo ON || echo OFF)
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=$([ "${USE_LTO}" == "1" ] && echo ON || echo OFF)
        -Dmpeghdec_BUILD_DECODER=ON
        -Dmpeghdec_BUILD_UIMANAGER=OFF
        -Dmpeghdec_BUILD_DOC=OFF
        -DUSE_PKGCONFIG_DEPS=ON
        -Dmpeghdec_BUILD_BINARIES=OFF
    )

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake -G Ninja "${myconf[@]}" .. || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

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
