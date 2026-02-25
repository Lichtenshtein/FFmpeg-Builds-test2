#!/bin/bash

SCRIPT_REPO="https://github.com/vapoursynth/vapoursynth.git"
SCRIPT_COMMIT="42a3bba6f0fffe3a397fa3494aadb7be1e2af8de"

ffbuild_depends() {
    echo zlib
    echo zimg
}

ffbuild_enabled() {
    # Поддерживаем только x86_64
    [[ $TARGET == win64 ]] && return 1
    return 1
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {

    # Чтобы FFmpeg работал с Vapoursynth, ему нужна библиотека VSScript.
    # Но VSScript требует Python. Мы отключаем модуль Python, но оставляем VSScript 
    # в режиме 'headers only' или минимальной статики, если это позволит Meson.
    mkdir -p build
    # Исправляем баг libtool/linker path для MinGW
    export LT_SYS_LIBRARY_PATH="$FFBUILD_PREFIX/lib"
    export CFLAGS="$CFLAGS -I$FFBUILD_PREFIX/include"
    export CXXFLAGS="$CXXFLAGS -I$FFBUILD_PREFIX/include"

        # --cross-file="$FFBUILD_CROSS_PREFIX"cross.meson
        # -Dcore=false
        # -Dtests=false

    meson setup build \
        --prefix="$FFBUILD_PREFIX" \
        --cross-file=/cross.meson \
        --buildtype release \
        --default-library static \
        -Denable_x86_asm=true \
        -Denable_vsscript=false \
        -Denable_vspipe=false \
        -Denable_python_module=false \
        || (tail -n 500 build/meson-logs/meson-log.txt && exit 1)

    ninja -C build -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja -C build install

    # Исправление pkg-config для статической линковки FFmpeg
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/vapoursynth.pc"

    if [[ -f "$PC_FILE" ]]; then
        # Убеждаемся, что пути корректны
        sed -i "s|/usr/include/python3.12||g" "$PC_FILE"
        # Добавляем стандартную библиотеку C++, так как VS написан на ней
        sed -i "s|^Libs:.*|Libs: -L\${libdir} -lvapoursynth -lstdc++ -lwinmm|" "$PC_FILE"
    fi
}

ffbuild_configure() {
    echo --enable-vapoursynth
}

ffbuild_unconfigure() {
    echo --disable-vapoursynth
}

ffbuild_cflags() {
    # Флаг для статической сборки, чтобы избежать __declspec(dllimport)
    echo "-DVAPOURSYNTH_STATIC"
}