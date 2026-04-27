#!/bin/bash

SCRIPT_REPO="https://github.com/vapoursynth/vapoursynth.git"
SCRIPT_COMMIT="1b93fd9649d4420b64863de9226e6e751ba2ba9d"

# Версия Python для встраивания (должна совпадать с той, что в Ubuntu 24.04 для сборки)
PY_VER="3.12"
PY_FULL_VER="3.12.3"
PY_LIB="python312" # Без точки для линковки

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
    mkdir -p python_win/bin python_win/include

    if [[ ! -f python_embed.zip || ! -f python_hdrs.zip ]]; then
        log_error "Required Python files missing! Check your download stage."
        return 1
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

    # Создаем фиктивный бинарник cython, который всегда выдает ошибку
    mkdir -p fake_bin
    cat <<EOF > fake_bin/cython
#!/bin/sh
if [ "\$1" = "-V" ] || [ "\$1" = "--version" ]; then
    echo "Cython version 3.0.10"
    exit 0
fi
exit 1
EOF
    chmod +x fake_bin/cython
    ln -sf cython fake_bin/cython3
    export PATH="${PWD}/fake_bin:${PATH}"

    # ПРИНУДИТЕЛЬНЫЙ pyconfig.h (чтобы Meson не лез в системный /usr/include)
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
#define HAVE_THREAD_H 1
#define WITH_THREAD 1
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
pkg-config = 'pkg-config'
cython = '${PWD}/fake_bin/cython'

[built-in options]
c_args = ['-I${CUR_DIR}/python_win/include', '-DMS_WIN64', '-DMS_WINDOWS']
cpp_args = ['-I${CUR_DIR}/python_win/include', '-DMS_WIN64', '-DMS_WINDOWS']
c_link_args = ['-L${CUR_DIR}', '-l${PY_LIB}']
cpp_link_args = ['-L${CUR_DIR}', '-l${PY_LIB}']
EOF

    export PKG_CONFIG_PATH="${CUR_DIR}/fake_pkgconfig"

    mkdir -p build && cd build

    export static_flags=""
    [[ "${PREFER_SHARED}" != "1" ]] && static_flags="-DVAPOURSYNTH_STATIC"

    # Мы собираем vsscript как SHARED, так как он ОБЯЗАН грузить python3.dll
    local myconf=(
        -Db_lto=$([ "${USE_LTO}" == "1" ] && echo true || echo false )
        --prefix="$FFBUILD_PREFIX"
        --cross-file="$FFBUILD_MESON_CROSS"
        --cross-file ../python_fix.ini
        --buildtype release
        --default-library $([ "${PREFER_SHARED}" == "1" ] && echo shared || echo static)
        -Dcpp_std=c++17
        -Dc_std=c11
        -Denable_vsscript=true
        -Denable_vspipe=false
        -Denable_x86_asm=true
        # -Denable_core=true
        -Denable_python_module=false # Requires Python, Cython, and the core
    )

    meson setup "${myconf[@]}" .. \
        -Dc_args="$CFLAGS $CPPFLAGS -DMS_WIN64 -DMS_WINDOWS $static_flags" \
        -Dcpp_args="$CXXFLAGS $CPPFLAGS -DMS_WIN64 -DMS_WINDOWS $static_flags" \
        -Dc_link_args="$LDFLAGS" \
        -Dcpp_link_args="$LDFLAGS" || return 1

    ninja $NINJA_V || return 1
    DESTDIR="$FFBUILD_DESTDIR" ninja install || return 1

    # Копируем DLL и критически важные файлы окружения Python
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin"
    
    # Все DLL (python312, python3, sqlite, ffi, ssl и т.д.)
    cp -v python_win/bin/*.dll "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin/"
    
    # Стандартная библиотека Python (БЕЗ НЕЁ НЕ ЗАРАБОТАЕТ)
    cp -v python_win/bin/python312.zip "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin/"
    
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
