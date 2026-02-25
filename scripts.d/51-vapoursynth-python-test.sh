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
    echo "download_file \"https://www.python.org/ftp/python/{PY_FULL_VER}/python-{PY_FULL_VER}-embed-amd64.zip\" \"python_embed.zip\""
}

ffbuild_dockerbuild() {

    # Готовим окружение Python для кросс-компиляции
    mkdir -p python_win && unzip -q python_embed.zip -d python_win

    # Создаем импортную либу для линкера из python312.dll
    ${FFBUILD_CROSS_PREFIX}gendef python_win/${PY_LIB}.dll > ${PY_LIB}.def
    ${FFBUILD_CROSS_PREFIX}dlltool -d ${PY_LIB}.def -l lib${PY_LIB}.a -D ${PY_LIB}.dll

    # Нам нужны хедеры. В Ubuntu они в /usr/include/python3.12
    # Но нам нужно убедиться, что Meson видит их для Windows
    local PY_INCLUDE="/usr/include/python${PY_VER}"
    # Исправляем баг libtool/linker path для MinGW
    export LT_SYS_LIBRARY_PATH="$FFBUILD_PREFIX/lib"
    export CFLAGS="$CFLAGS -I$FFBUILD_PREFIX/include"
    export CXXFLAGS="$CXXFLAGS -I$FFBUILD_PREFIX/include"

    # Создаем файл конфигурации для Meson, чтобы он "нашел" Python
    # Мы обманываем Meson, подсовывая ему пути к системным хедерам и виндовым либам
    cat <<EOF > python_cross.ini
[binaries]
python3 = '/usr/bin/python3'

[properties]
# Форсируем пути для кросс-компиляции
python_includedir = '$PY_INCLUDE'
python_libdir = '$(pwd)'
EOF

    mkdir -p build

        # --cross-file="$FFBUILD_CROSS_PREFIX"cross.meson
        # -Dcore=true

    # Мы собираем vsscript как SHARED, так как он ОБЯЗАН грузить python3.dll
    meson setup build \
        --prefix="$FFBUILD_PREFIX" \
        --cross-file=/cross.meson \
        --cross-file python_cross.ini \
        --buildtype release \
        --default-library static \
        -Denable_vsscript=true \
        -Denable_vspipe=false \
        -Denable_x86_asm=true \
        -Denable_python_module=false \
        -Dpython3_bin='/usr/bin/python3' \
        || (tail -n 500 build/meson-logs/meson-log.txt && exit 1)

    ninja -C build -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja -C build install

    # Копируем необходимые DLL для работы .vpy
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin"
    cp python_win/python3.dll "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin/"
    cp python_win/python${PY_VER//./}.dll "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin/" 2>/dev/null || true
    # cp python_win/*.dll "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin/"

    # Генерация правильных .pc файлов вручную, чтобы FFmpeg не запутался
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
Libs.private: -L$(pwd) -l${PY_LIB} -lstdc++
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