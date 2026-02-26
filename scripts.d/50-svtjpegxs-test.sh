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
    # Исправляем CMakeLists.txt: отключаем автоматическое определение архитектуры хоста
    # Это критично для кросс-компиляции, чтобы он не взял флаги процессора GitHub раннера
    sed -i 's/-march=native//g' CMakeLists.txt || true

    mkdir build && cd build

    # Специальные флаги для MinGW, чтобы избежать сегфолтов (выравнивание стека)
    local EXTRA_C_FLAGS="$CFLAGS -mstackrealign -fno-asynchronous-unwind-tables"
    local EXTRA_CXX_FLAGS="$CXXFLAGS -mstackrealign -fno-asynchronous-unwind-tables"

    local cmake_flags=(
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_C_FLAGS="$EXTRA_C_FLAGS"
        -DCMAKE_CXX_FLAGS="$EXTRA_CXX_FLAGS"
        -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS"
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX"
        -DBUILD_SHARED_LIBS=OFF
        -DBUILD_TESTING=OFF
        -DBUILD_APPS=OFF
        # Принудительно отключаем AVX-512, так как на Xeon E5 v4 его нет
        -DENABLE_AVX512=OFF
    )

    cmake "${cmake_flags[@]}" ..
    make -j$(nproc) $MAKE_V
    make install DESTDIR="$FFBUILD_DESTDIR"

    # ФИКС pkg-config (у SVT-JPEG-XS часто раздельные файлы)
    # Нам нужно, чтобы FFmpeg видел их корректно
    for pc in "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/"SvtJpegxs*.pc; do
        [[ -f "$pc" ]] || continue
        # Исправляем префикс
        sed -i "s|^prefix=.*|prefix=$FFBUILD_PREFIX|" "$pc"
        # Добавляем системные библиотеки
        echo "Libs.private: -lstdc++ -lpthread -lm" >> "$pc"
    done
    
    # FFmpeg иногда ищет просто svtjpegxs.pc. Создадим алиас.
    if [[ -f "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/SvtJpegxsEnc.pc" ]]; then
        cp "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/SvtJpegxsEnc.pc" \
           "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/svtjpegxs.pc"
    fi
}

ffbuild_configure() {
    echo --enable-libsvtjpegxs
}

ffbuild_unconfigure() {
    echo --disable-libsvtjpegxs
}