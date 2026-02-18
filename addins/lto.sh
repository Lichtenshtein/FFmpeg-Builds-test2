#!/bin/bash

# Флаг для FFmpeg
FF_CONFIGURE="--enable-lto"

# Флаги для ВСЕХ промежуточных библиотек (scripts.d)
# Используем переменные, которые подхватит наш новый collect_all_flags в generate.sh
FF_CFLAGS="-flto=auto"
FF_CXXFLAGS="-flto=auto"
FF_LDFLAGS="-flto=auto"

# Настройка инструментов тулчейна
# LTO в GCC требует использования gcc-ar/nm/ranlib (плагинов), 
# иначе статические библиотеки (.a) будут "битыми" для линковщика.
export AR="${FFBUILD_TOOLCHAIN}-gcc-ar"
export NM="${FFBUILD_TOOLCHAIN}-gcc-nm"
export RANLIB="${FFBUILD_TOOLCHAIN}-gcc-ranlib"

# Фикс для некоторых скриптов, которые игнорируют внешние AR/NM
ffbuild_configure() {
    # Пробрасываем обертки инструментов прямо в конфиги компонентов
    echo "--ar=$AR --nm=$NM --ranlib=$RANLIB"
}
