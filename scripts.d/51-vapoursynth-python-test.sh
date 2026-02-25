#!/bin/bash

# CACHE_BUSTER: 2026-02-25-v3 (если нужно снова сбросить кэш)

SCRIPT_REPO="https://github.com/vapoursynth/vapoursynth.git"
SCRIPT_COMMIT="42a3bba6f0fffe3a397fa3494aadb7be1e2af8de"

# Версия Python для встраивания (должна совпадать с той, что в Ubuntu 24.04 для сборки)
PY_VER="3.12"
PY_FULL_VER="3.12.3"
PY_LIB="python312" # Без точки для линковки

ffbuild_depends() {
    echo zlib
    echo zimg
}

ffbuild_enabled() {
    # Поддерживаем только x86_64
    [[ $TARGET == win64 ]] && return 0
    return 1
}

ffbuild_dockerdl() {
    default_dl .
    # Добавляем команду очистки ПЕРЕД скачиванием тяжелых файлов
    echo "git clean -fdx"
    # Загружаем Windows-версию Python (embed), чтобы забрать оттуда dll и либы для кросс-компиляции
    echo "download_file \"https://www.python.org/ftp/python/${PY_FULL_VER}/python-${PY_FULL_VER}-embed-amd64.zip\" \"python_embed.zip\""
    # echo "download_file \"https://www.python.org/ftp/python/${PY_FULL_VER}/python-${PY_FULL_VER}.tar.xz\" \"python_src.tar.xz\""
    # Хедеры из официального репозитория (ветка 3.12)
    echo "download_file \"https://github.com/python/cpython/archive/refs/tags/v${PY_FULL_VER}.zip\" \"python_hdrs.zip\""
}

ffbuild_dockerbuild() {
    mkdir -p python_win/bin python_win/include
    
    if [[ ! -f python_embed.zip || ! -f python_hdrs.zip ]]; then
        log_error "Required Python files missing! Check your download stage."
        exit 1
    fi

    # Распаковка DLL
    unzip -qo python_embed.zip -d python_win/bin
    
    # Распаковка хедеров (используем универсальный путь через *)
    mkdir -p temp_hdrs
    unzip -qo python_hdrs.zip -d temp_hdrs
    
    # чтобы не зависеть от того, cpython-3.12 это или cpython-3.12.3
    mv temp_hdrs/cpython-*/Include/* python_win/include/
    
    # Проверяем, есть ли там PC/pyconfig.h (иногда он там) или создаем свой
    # В Windows-сборке CPython pyconfig.h обычно генерируется, нам нужен статический вариант
    cp temp_hdrs/cpython-*/PC/pyconfig.h python_win/include/ 2>/dev/null || true
    rm -rf temp_hdrs

    # ПРИНУДИТЕЛЬНЫЙ pyconfig.h (чтобы Meson не лез в системный /usr/include)
    cat <<EOF > python_win/include/pyconfig.h
#ifndef Py_PYCONFIG_H
#define Py_PYCONFIG_H
#define MS_WIN64
#define MS_WINDOWS
#define Py_ENABLE_SHARED
#define SIZEOF_WCHAR_T 2
#include <patchlevel.h>
#endif
EOF

    # Решаем проблему Windows.h (Case-sensitivity)
    local SYSTEM_WIN_H=$(find /opt/ct-ng -name "windows.h" | head -n 1)
    if [[ -f "$SYSTEM_WIN_H" ]]; then
        ln -sf "$SYSTEM_WIN_H" python_win/include/Windows.h
    fi

    # Генерируем библиотеку импорта
    ${FFBUILD_CROSS_PREFIX}gendef python_win/bin/${PY_LIB}.dll > ${PY_LIB}.def
    ${FFBUILD_CROSS_PREFIX}dlltool -d ${PY_LIB}.def -l lib${PY_LIB}.a -D ${PY_LIB}.dll

    local CUR_DIR=$(pwd)

    # Настройка Meson (fake_pkgconfig)
    mkdir -p fake_pkgconfig
    cat <<EOF > fake_pkgconfig/python3.pc
Name: python3
Version: ${PY_VER}
Description: Fake Python
Libs: -L${CUR_DIR} -l${PY_LIB}
Cflags: -I${CUR_DIR}/python_win/include
EOF
    # Создаем все возможные варианты имен .pc файлов
    ln -sf python3.pc fake_pkgconfig/python-3.12.pc
    ln -sf python3.pc fake_pkgconfig/python-3.12-embed.pc

    cat <<EOF > python_fix.ini
[binaries]
pkgconfig = 'pkg-config'

[built-in options]
c_args = ['-I${CUR_DIR}/python_win/include', '-DMS_WIN64', '-DMS_WINDOWS']
cpp_args = ['-I${CUR_DIR}/python_win/include', '-DMS_WIN64', '-DMS_WINDOWS']
c_link_args = ['-L${CUR_DIR}', '-l${PY_LIB}']
cpp_link_args = ['-L${CUR_DIR}', '-l${PY_LIB}']
EOF

    export PKG_CONFIG_PATH="${CUR_DIR}/fake_pkgconfig"
    mkdir -p build

    # Мы собираем vsscript как SHARED, так как он ОБЯЗАН грузить python3.dll
    meson setup build \
        --prefix="$FFBUILD_PREFIX" \
        --cross-file=/cross.meson \
        --cross-file python_fix.ini \
        --buildtype release \
        --default-library static \
        -Denable_vsscript=true \
        -Denable_vspipe=false \
        -Denable_x86_asm=true \
        -Denable_python_module=false \
        || (tail -n 500 build/meson-logs/meson-log.txt && exit 1)

    ninja -C build -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja -C build install

    # Копируем необходимые DLL для работы .vpy
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin"
    # cp python_win/bin/${PY_LIB}.dll "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin/"
    # cp python_win/bin/python3.dll "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin/"
    cp python_win/bin/*.dll "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin/"

    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig"
    
    cat <<EOF > "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/vapoursynth.pc"
prefix=$FFBUILD_PREFIX
libdir=\${prefix}/lib
includedir=\${prefix}/include/vapoursynth
Name: vapoursynth
Description: A frameserver for the 21st century
Version: 74
Libs: -L\${libdir} -lvapoursynth
Libs.private: -lstdc++ -lwinmm
Cflags: -I\${includedir} -DVAPOURSYNTH_STATIC
EOF

    cat <<EOF > "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/vapoursynth-script.pc"
prefix=$FFBUILD_PREFIX
libdir=\${prefix}/lib
includedir=\${prefix}/include/vapoursynth
Name: vapoursynth-script
Description: Library for interfacing VapourSynth with Python
Version: 74
Libs: -L\${libdir} -lvsscript
Libs.private: -l${PY_LIB} -lstdc++
Cflags: -I\${includedir}
EOF
}

ffbuild_configure() {
    echo --enable-vapoursynth
}

ffbuild_unconfigure() {
    echo --disable-vapoursynth
}

ffbuild_cflags() {
    echo "-DVAPOURSYNTH_STATIC"
}

ffbuild_libs() {
    # Для успешной линковки FFmpeg с поддержкой VSScript
    echo "-lvsscript -lstdc++"
}