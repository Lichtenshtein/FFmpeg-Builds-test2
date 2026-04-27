#!/bin/bash

SCRIPT_REPO="https://github.com/vapoursynth/vapoursynth.git"
SCRIPT_COMMIT="97296f703eff3ea8c065c65cdfa244b4de3756f4"

# Версия Python для встраивания (должна совпадать с той, что в Ubuntu 24.04 для сборки)
PY_VER="3.14"
PY_FULL_VER="3.14.1"
PY_LIB="python314" # Без точки для линковки

ffbuild_depends() {
    echo zlib
    echo avisynth
    echo zimg
}

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    default_dl .
    # Добавляем команду очистки ПЕРЕД скачиванием тяжелых файлов
    echo "git clean -fdx"
    # Загружаем Windows-версию Python (embed), чтобы забрать оттуда dll и либы для кросс-компиляции
    echo "download_file \"https://www.python.org/ftp/python/${PY_FULL_VER}/python-${PY_FULL_VER}-embed-amd64.zip\" \"python_embed.zip\""
    # Хедеры из официального репозитория (ветка 3.12)
    echo "download_file \"https://github.com/python/cpython/archive/refs/tags/v${PY_FULL_VER}.zip\" \"python_hdrs.zip\""
}

ffbuild_dockerbuild() {
    set -e

    # Подготовка структуры Python
    mkdir -p python_win/bin python_win/include
    unzip -qo python_embed.zip -d python_win/bin
    
    mkdir -p temp_hdrs
    unzip -qo python_hdrs.zip -d temp_hdrs
    mv temp_hdrs/cpython-*/Include/* python_win/include/
    cp temp_hdrs/cpython-*/PC/pyconfig.h python_win/include/ 2>/dev/null || true
    rm -rf temp_hdrs

    local CUR_DIR=$(pwd)

    # Хирургическое удаление Cython из проекта
    sed -i "s/'cython'//g; s/, 'cython'//g; s/'cython',//g" meson.build

    # Фикс регистра для Windows.h (Критично для сборки Core)
    local MINGW_INCLUDE=$(find /opt/ct-ng -name "Windows.h" -exec dirname {} \; | head -n 1)
    mkdir -p extra_include
    # Делаем так, чтобы и <windows.h> и <Windows.h> работали
    ln -sf "${MINGW_INCLUDE}/Windows.h" "extra_include/windows.h"
    ln -sf "${MINGW_INCLUDE}/Windows.h" "extra_include/Windows.h"
    ln -sf "${MINGW_INCLUDE}/WinType.h" "extra_include/wintype.h"
    ln -sf "${MINGW_INCLUDE}/WinType.h" "extra_include/WinType.h"
    ln -sf "${MINGW_INCLUDE}/Windows.h" "./Windows.h"
    ln -sf "${MINGW_INCLUDE}/Windows.h" "Windows.h"
    ln -sf "${MINGW_INCLUDE}/Windows.h" "windows.h"
    # Ссылка для самого Python, чтобы он видел Windows.h внутри своих инклудов
    ln -sf "${MINGW_INCLUDE}/Windows.h" python_win/include/Windows.h

    # Генерация библиотек импорта Python
    ${FFBUILD_CROSS_PREFIX}gendef python_win/bin/${PY_LIB}.dll > ${PY_LIB}.def
    ${FFBUILD_CROSS_PREFIX}dlltool -d ${PY_LIB}.def -l lib${PY_LIB}.a -D ${PY_LIB}.dll

    # Создание правильного pyconfig.h
    cat <<EOF > python_win/include/pyconfig.h
#ifndef Py_PYCONFIG_H
#define Py_PYCONFIG_H
#define MS_WIN64
#define MS_WINDOWS
#define Py_ENABLE_SHARED
#define SIZEOF_VOID_P 8
#define SIZEOF_SIZE_T 8
#define SIZEOF_LONG 4
#define SIZEOF_WCHAR_T 2
#define WIN32_THREADS 1
#define WITH_THREAD 1
#include <patchlevel.h>
#endif
EOF

    mkdir -p fake_pkgconfig
    cat <<EOF > fake_pkgconfig/python3.pc
prefix=${CUR_DIR}/python_win
libdir=${CUR_DIR}
includedir=\${prefix}/include

Name: python3
Version: 3.14
Description: Fake Python
Libs: -L\${libdir} -l${PY_LIB}
Cflags: -I\${includedir} -DMS_WIN64 -DMS_WINDOWS
EOF

    ln -sf python3.pc fake_pkgconfig/python-3.14.pc

    cat <<EOF > python_fix.ini
[binaries]
pkg-config = 'pkg-config'

[properties]
pkg_config_libdir = ['${CUR_DIR}/fake_pkgconfig', '/opt/ffbuild/lib/pkgconfig', '/opt/ffbuild/share/pkgconfig']
pkg_config_static = true

[built-in options]
c_args = ['-I${CUR_DIR}/python_win/include', '-DMS_WIN64', '-DMS_WINDOWS']
cpp_args = ['-I${CUR_DIR}/python_win/include', '-DMS_WIN64', '-DMS_WINDOWS']
c_link_args = ['-L${CUR_DIR}', '-l${PY_LIB}']
cpp_link_args = ['-L${CUR_DIR}', '-l${PY_LIB}']
EOF

    # Очищаем системные пути, чтобы Meson не видел Linux-заголовки
    export PKG_CONFIG_LIBDIR="${CUR_DIR}/fake_pkgconfig"
    export PKG_CONFIG_PATH=""
    export PKG_CONFIG_ALLOW_SYSTEM_CFLAGS=0
    export PKG_CONFIG_ALLOW_SYSTEM_LIBS=0

    FIX_FLAGS="-I${CUR_DIR} -D_WIN32 -D_WIN64 -DUNICODE -D_UNICODE"

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DVAPOURSYNTH_STATIC"

    mkdir -p build && cd build

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --cross-file="$FFBUILD_MESON_CROSS"
        --cross-file ../python_fix.ini
        --buildtype release
        --default-library $([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false )
        -Dcpp_std=c++17
        -Dc_std=c11
        -Denable_vsscript=true
        -Denable_vspipe=false
        -Denable_x86_asm=true
        # -Denable_core=true
        -Dpython.platlibdir="${CUR_DIR}/python_win"
        -Dpython.purelibdir="${CUR_DIR}/python_win"
        -Denable_python_module=false
        -Dpython.install_env=auto
        -Dpython.bytecompile=0
    )

    unset CPATH
    unset C_INCLUDE_PATH
    unset CPLUS_INCLUDE_PATH

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS $FIX_FLAGS $static_flags" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS $FIX_FLAGS $static_flags" \
        -Dc_link_args="$LDFLAGS" \
        -Dcpp_link_args="$LDFLAGS" || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # Копируем DLL и критически важные файлы окружения Python
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin"
    
    # Все DLL (python312, python3, sqlite, ffi, ssl и т.д.)
    cp -v python_win/bin/*.dll "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin/"
    
    # Стандартная библиотека Python (БЕЗ НЕЁ НЕ ЗАРАБОТАЕТ)
    cp -v python_win/bin/python314.zip "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin/"
    
    # Расширения .pyd, если они нужны внутри .vpy скриптов
    cp -v python_win/bin/*.pyd "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin/" 2>/dev/null || true

    mkdir -p "$PC_DIR"
    cat <<EOF > "$PC_DIR/vapoursynth.pc"
prefix=$FFBUILD_PREFIX
libdir=\${prefix}/lib
includedir=\${prefix}/include/vapoursynth
Name: vapoursynth
Description: A frameserver for the 21st century
Version: $VER_FULL
Libs: -L\${libdir} -lvapoursynth
Libs.private: -lstdc++ -lwinmm
Cflags: -I\${includedir} $static_flags
EOF

    cat <<EOF > "$PC_DIR/vapoursynth-script.pc"
prefix=$FFBUILD_PREFIX
libdir=\${prefix}/lib
includedir=\${prefix}/include/vapoursynth
Name: vapoursynth-script
Description: Library for interfacing VapourSynth with Python
Version: $VER_FULL
Libs: -L\${libdir} -lvsscript
Libs.private: -l${PY_LIB} -lstdc++
Cflags: -I\${includedir}
EOF
}

ffbuild_cflags() {
    echo "$static_flags"
}

ffbuild_libs() {
    echo "-lvsscript"
}

ffbuild_configure() {
    echo --enable-vapoursynth
}

ffbuild_unconfigure() {
    echo --disable-vapoursynth
}
