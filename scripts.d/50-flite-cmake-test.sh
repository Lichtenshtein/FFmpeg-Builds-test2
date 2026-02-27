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
    if [[ -d "/builder/patches/flite-test" ]]; then
        for patch in /builder/patches/flite-test/*.patch; do
            log_info "APPLYING PATCH: $patch"
            if patch -p1 -N -r - < "$patch"; then
                log_info "${GREEN}${CHECK_MARK} SUCCESS: Patch applied.${NC}"
            else
                log_error "${RED}${CROSS_MARK} ERROR: PATCH FAILED! ${CROSS_MARK}${NC}"
                # return 1 # если нужно прервать сборку при ошибке
            fi
        done
    fi

    # Исправляем POSIX-зависимость в сокетах для Windows
    # отключаем содержимое файла, так как WITH_AUDIO=OFF все равно делает его ненужным
    echo "/* Disabled for MinGW */" > src/utils/cst_socket.c

    # Создаем стандартную структуру для CMake
    mkdir build && cd build

    # Настраиваем CMake для MinGW
    # -DCMAKE_POSITION_INDEPENDENT_CODE=ON для статики
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
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        ..

    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # некоторые порты Flite ставят либы в /lib/x86_64-w64-mingw32/
    # Переносим их в стандартный /lib, чтобы FFmpeg их нашел
    if [ -d "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/x86_64-w64-mingw32" ]; then
        mv "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/x86_64-w64-mingw32"/* "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/"
        rm -rf "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/x86_64-w64-mingw32"
    fi
    # Генерация правильного pkg-config (добавляем все необходимые части либы)
    # Flite после сборки CMake часто разбивается на несколько .a файлов, 
    # но нам нужен основной flite
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig"
    cat <<EOF > "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/flite.pc"
prefix=$FFBUILD_PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: flite
Description: Festival Lite Speech Synthesis System
Version: 2.1.0
Libs: -L\${libdir} -lflite -lm -lws2_32
Cflags: -I\${includedir}
EOF
}

ffbuild_configure() {
    echo --enable-libflite
}

ffbuild_unconfigure() {
    echo --disable-libflite
}
