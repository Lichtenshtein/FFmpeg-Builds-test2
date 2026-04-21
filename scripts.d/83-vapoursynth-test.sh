#!/bin/bash

SCRIPT_REPO="https://github.com/vapoursynth/vapoursynth.git"
SCRIPT_COMMIT="42a3bba6f0fffe3a397fa3494aadb7be1e2af8de"

ffbuild_depends() {
    echo zlib
    echo avisynth
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
    set -e
    # Чтобы FFmpeg работал с Vapoursynth, ему нужна библиотека VSScript.
    # Но VSScript требует Python. Мы отключаем модуль Python, но оставляем VSScript 
    # в режиме 'headers only' или минимальной статики, если это позволит Meson.
    mkdir -p build && cd build
    # Исправляем баг libtool/linker path для MinGW
    export LT_SYS_LIBRARY_PATH="$FFBUILD_PREFIX/lib"

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DVAPOURSYNTH_STATIC"

        # --cross-file="$FFBUILD_CROSS_PREFIX"cross.meson
        # -Dcore=false
        # -Dtests=false

    local myconf=(
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false )
        --prefix="$FFBUILD_PREFIX"
        --cross-file="$FFBUILD_MESON_CROSS"
        --buildtype release
        --default-library $([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        -Dc_std=c11
        -Denable_x86_asm=true
        -Denable_vsscript=false
        -Denable_vspipe=false
        -Denable_core=true
        -Denable_python_module=false # Requires Python, Cython, and the core
    )

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS $static_flags" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS $static_flags" \
        -Dc_link_args="$LDFLAGS" \
        -Dcpp_link_args="$LDFLAGS" || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # Исправление pkg-config для статической линковки FFmpeg
    local PC_FILE="$PC_DIR/vapoursynth.pc"

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
    echo "$static_flags"
}