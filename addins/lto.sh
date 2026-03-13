#!/bin/bash

# Флаг для FFmpeg
FF_CONFIGURE="--enable-lto"

# Флаги для ВСЕХ промежуточных библиотек (scripts.d)
# Используем переменные, которые подхватит наш новый collect_all_flags в generate.sh
FF_CFLAGS="${FF_CFLAGS:+$FF_CFLAGS }-flto=auto"
FF_CXXFLAGS="${FF_CXXFLAGS:+$FF_CXXFLAGS }-flto=auto"
FF_LDFLAGS="${FF_LDFLAGS:+$FF_LDFLAGS }-flto=auto"

# Настройка инструментов тулчейна
# LTO в GCC требует использования gcc-ar/nm/ranlib (плагинов), 
# иначе статические библиотеки (.a) будут "битыми" для линковщика.
export AR="${FFBUILD_TOOLCHAIN}-gcc-ar"
export NM="${FFBUILD_TOOLCHAIN}-gcc-nm"
export RANLIB="${FFBUILD_TOOLCHAIN}-gcc-ranlib"
