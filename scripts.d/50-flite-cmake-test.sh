#!/bin/bash

# Используем CMake-порт для стабильной кросс-компиляции
SCRIPT_REPO="https://github.com/univrsal/flite.git"
SCRIPT_COMMIT="a9d8a3b60a859ee1bd1d4a1379996902c4acb6e2"

ffbuild_enabled() {
    return 1
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    # Исправляем POSIX-зависимость в сокетах для Windows
    # отключаем содержимое файла, так как WITH_AUDIO=OFF все равно делает его ненужным
    echo "/* Disabled for MinGW */" > src/utils/cst_socket.c

    # Создаем стандартную структуру для CMake
    mkdir build && cd build

    CFLAGS="$CFLAGS $CPPFLAGS" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS" \
    LDFLAGS="$LDFLAGS" \
    cmake \
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
        -DINSTALL_EXAMPLES=OFF \
        -DWITH_AUDIO=OFF \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        .. || return 1

    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    # некоторые порты Flite ставят либы в /lib/x86_64-w64-mingw32/
    # Переносим их в стандартный /lib, чтобы FFmpeg их нашел
    if [ -d "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/x86_64-w64-mingw32" ]; then
        mv "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/x86_64-w64-mingw32"/* "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/"
        rm -rf "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/x86_64-w64-mingw32"
    fi
    # Генерация правильного pkg-config (добавляем все необходимые части либы)
    # Flite после сборки CMake часто разбивается на несколько .a файлов, 
    # но нам нужен основной flite
    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/flite.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: flite
Description: Festival Lite Speech Synthesis System
Version: 2.1.0
Libs: -L\${libdir} -lflite
Cflags: -I\${includedir}
EOF

}

ffbuild_configure() {
    echo --enable-libflite
}

ffbuild_unconfigure() {
    echo --disable-libflite
}
