#!/bin/bash

SCRIPT_REPO="https://github.com/vapoursynth/vapoursynth.git"
SCRIPT_COMMIT="42a3bba6f0fffe3a397fa3494aadb7be1e2af8de"

# Версия Python для встраивания (должна совпадать с той, что в Ubuntu 24.04 для сборки)
PY_VER="3.12"
PY_FULL_VER="3.12.3"

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
    
    # Нам нужны хедеры. В Ubuntu они в /usr/include/python3.12
    # Но нам нужно убедиться, что Meson видит их для Windows
    local PY_INCLUDE="/usr/include/python${PY_VER}"

    # Создаем файл конфигурации для Meson, чтобы он "нашел" Python
    # Мы обманываем Meson, подсовывая ему пути к системным хедерам и виндовым либам
    cat <<EOF > python_cross.ini
[binaries]
python3 = '/usr/bin/python3'

[properties]
python_path = '$PY_INCLUDE'
EOF

    # Исправляем баг libtool/linker path для MinGW
    export LT_SYS_LIBRARY_PATH="$FFBUILD_PREFIX/lib"

    # Мы собираем vsscript как SHARED, так как он ОБЯЗАН грузить python3.dll
    meson setup build \
        --prefix="$FFBUILD_PREFIX" \
        --cross-file="$FFBUILD_CROSS_PREFIX"cross.meson \
        --cross-file python_cross.ini \
        --buildtype release \
        --default-library static \
        -Dcore=true \
        -Denable_vsscript=true \
        -Denable_python_module=true \
        -Dpython3_bin='/usr/bin/python3' \
        || (tail -n 500 build/meson-logs/meson-log.txt && exit 1)

    ninja -C build -j$(nproc) $NINJA_V
    DESTDIR="$FFBUILD_DESTDIR" ninja -C build install

    # Копируем необходимые DLL для работы .vpy
    mkdir -p "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin"
    cp python_win/python3.dll "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin/"
    cp python_win/python${PY_VER//./}.dll "$FFBUILD_DESTDIR$FFBUILD_PREFIX/bin/" 2>/dev/null || true
    
    # Исправление pkg-config для статической линковки FFmpeg
    local PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/vapoursynth.pc"
    local VSS_PC_FILE="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/vapoursynth-script.pc"

    local VSS_PC="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig/vapoursynth-script.pc"
    if [[ -f "$VSS_PC" ]]; then
        # Добавляем -lpython3 в зависимости, чтобы FFmpeg знал, с чем линковаться
        sed -i "s|^Libs:.*|Libs: -L\${libdir} -lvsscript -lstdc++|" "$VSS_PC"
    fi
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