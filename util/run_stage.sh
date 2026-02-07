#!/bin/bash
set -e # Убираем -x для чистоты логов, оставим только для ошибок

export RAW_CFLAGS="$CFLAGS"
export RAW_CXXFLAGS="$CXXFLAGS"
export RAW_LDFLAGS="$LDFLAGS"

# Добавляем флаги этапа
[[ -n "$STAGE_CFLAGS" ]] && export CFLAGS="$CFLAGS $STAGE_CFLAGS"
[[ -n "$STAGE_CXXFLAGS" ]] && export CXXFLAGS="$CXXFLAGS $STAGE_CXXFLAGS"
[[ -n "$STAGE_LDFLAGS" ]] && export LDFLAGS="$LDFLAGS $STAGE_LDFLAGS"

STAGENAME="$(basename "$1" | sed 's/.sh$//')"
# Работаем в выделенной директории сборки
mkdir -p "/build/$STAGENAME"
cd "/build/$STAGENAME"

# Распаковка кэша исходников, если он есть (из .cache/downloads)
# Мы ищем архив по имени этапа
DL_CACHE="/root/.cache/downloads/${STAGENAME}.tar.xz"
if [[ -f "$DL_CACHE" ]]; then
    echo "Using source cache for $STAGENAME"
    tar xaf "$DL_CACHE" -C .
fi

git config --global --add safe.directory "$PWD"

# Загружаем функции этапа
source "$1"

# Выполняем сборку
if [[ -z "$2" ]]; then
    ffbuild_dockerbuild
else
    "$2"
fi

# Вместо копирования всего в корень, мы просто гарантируем, 
# что артефакты попали в FFBUILD_PREFIX (/opt/ffbuild)
# Большинство скриптов в FFmpeg-build-helpers сами делают 'make install' в префикс.

# Очистка исходников ПОСЛЕ сборки этапа, чтобы не забивать диск
cd /
rm -rf "/build/$STAGENAME"
