#!/bin/bash

SCRIPT_REPO="https://github.com/OpenVisualCloud/SVT-JPEG-XS.git"
SCRIPT_COMMIT="b1b227840463d3b74a4da13d8d1f17610697a793"

ffbuild_enabled() {
    [[ $TARGET == win32 ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e
    # Исправляем CMakeLists.txt: отключаем автоматическое определение архитектуры хоста
    # Это критично для кросс-компиляции, чтобы он не взял флаги процессора GitHub раннера
    sed -i 's/-march=native//g' CMakeLists.txt || true

    mkdir build && cd build

    local cmake_flags=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=OFF
        -DBUILD_TESTING=OFF
        -DBUILD_APPS=OFF
        -DENABLE_AVX512=$([ "${USE_AVX512}" == "1" ] && echo ON || echo OFF )
        -DENABLE_NATIVE=OFF
        -DENABLE_NASM=ON
    )

    # Специальные флаги для MinGW, чтобы избежать сегфолтов (выравнивание стека)
    CFLAGS="$CFLAGS $CPPFLAGS -mstackrealign -fno-asynchronous-unwind-tables" \
    CXXFLAGS="$CXXFLAGS $CPPFLAGS -mstackrealign -fno-asynchronous-unwind-tables" \
    LDFLAGS="$LDFLAGS" \
    cmake "${cmake_flags[@]}" .. || return 1
    make -j$(nproc) $MAKE_V || return 1
    make install DESTDIR="$FFBUILD_DESTDIR" || return 1

    for pc in "$PC_DIR/"SvtJpegxs*.pc; do
        [[ -f "$pc" ]] || continue
        # Исправляем префикс
        sed -i "s|^prefix=.*|prefix=$FFBUILD_PREFIX|" "$pc"
    done

    # FFmpeg иногда ищет просто svtjpegxs.pc. Создадим алиас.
    if [[ -f "$PC_DIR/SvtJpegxsEnc.pc" ]]; then
        cp "$PC_DIR/SvtJpegxsEnc.pc" \
           "$PC_DIR/svtjpegxs.pc"
    fi

}

ffbuild_configure() {
    echo --enable-libsvtjpegxs
}

ffbuild_unconfigure() {
    echo --disable-libsvtjpegxs
}