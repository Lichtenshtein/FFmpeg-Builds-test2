#!/bin/bash

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
    # Загружаем Windows-версию Python (embed), чтобы забрать оттуда dll и либы для кросс-компиляции
    echo "download_file \"https://www.python.org/ftp/python/${PY_FULL_VER}/python-${PY_FULL_VER}-embed-amd64.zip\" \"python_embed.zip\""
    echo "download_file \"https://www.python.org/ftp/python/${PY_FULL_VER}/python-${PY_FULL_VER}-amd64.exe\" \"python_win.exe\""
}

ffbuild_dockerbuild() {
    if [[ ! -f python_embed.zip ]]; then
        log_error "python_embed.zip NOT FOUND. Download failed or cache is stale."
        exit 1
    fi

    # Готовим окружение Python для кросс-компиляции
    mkdir -p python_win/bin
    unzip -q python_embed.zip -d python_win/bin
    
    # Извлекаем Include файлы из инсталлера
    7z x python_win.exe -opython_win include/*.h -r
    [[ -d python_win/include/include ]] && mv python_win/include/include/* python_win/include/

    # Генерируем либу
    ${FFBUILD_CROSS_PREFIX}gendef python_win/bin/${PY_LIB}.dll > ${PY_LIB}.def
    ${FFBUILD_CROSS_PREFIX}dlltool -d ${PY_LIB}.def -l lib${PY_LIB}.a -D ${PY_LIB}.dll

    local CUR_DIR=$(pwd)

    # Создаем файл-заглушку, чтобы pkg-config не нашел системный питон
    mkdir -p fake_pkgconfig
    cat <<EOF > fake_pkgconfig/python3.pc
Name: python3
Description: Fake Python
Version: ${PY_VER}
Libs: -L${CUR_DIR} -l${PY_LIB}
Cflags: -I${CUR_DIR}/python_win/include
EOF
    ln -sf python3.pc fake_pkgconfig/python-3.12.pc
    ln -sf python3.pc fake_pkgconfig/python-3.12-embed.pc

    cat <<EOF > python_fix.ini
[binaries]
pkgconfig = 'pkg-config'

[built-in options]
c_args = ['-isystem${CUR_DIR}/python_win/include', '-DMS_WIN64', '-DPy_NO_ENABLE_SHARED']
cpp_args = ['-isystem${CUR_DIR}/python_win/include', '-DMS_WIN64', '-DPy_NO_ENABLE_SHARED']
c_link_args = ['-L${CUR_DIR}', '-l${PY_LIB}']
cpp_link_args = ['-L${CUR_DIR}', '-l${PY_LIB}']
EOF

    mkdir -p build

    # Добавляем наш фейковый путь в PKG_CONFIG_PATH
    export PKG_CONFIG_PATH="${CUR_DIR}/fake_pkgconfig"

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