#!/bin/bash

# Используем CMake-порт для стабильной кросс-компиляции
SCRIPT_REPO="https://github.com/univrsal/flite.git"
SCRIPT_COMMIT="a9d8a3b60a859ee1bd1d4a1379996902c4acb6e2"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    # Создаем стандартную структуру для CMake
    mkdir build && cd build

    # Настраиваем CMake для MinGW
    cmake \
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$CFLAGS" \
        -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
        -DBUILD_SHARED_LIBS=OFF \
        -DINSTALL_EXAMPLES=OFF \
        -DWITH_AUDIO=OFF \
        ..

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"
    
    # FFmpeg ожидает flite.pc, но cmake-порт может его не создать.
    # Если его нет, создадим вручную минимальный файл для pkg-config
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig"
    if [ ! -f "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/flite.pc" ]; then
        cat <<EOF > "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/flite.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: flite
Description: Festival Lite Speech Synthesis System
Version: 2.1.0
Libs: -L\${libdir} -lflite -lm
Cflags: -I\${includedir}
EOF
    fi
}

ffbuild_configure() {
    echo --enable-libflite
}

ffbuild_unconfigure() {
    echo --disable-libflite
}
