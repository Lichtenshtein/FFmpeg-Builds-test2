#!/bin/bash
set -e

SCRIPT_PATH="$1"
STAGENAME="$(basename "$SCRIPT_PATH" | sed 's/.sh$//')"

# Подготовка папки сборки
mkdir -p "/build/$STAGENAME"
cd "/build/$STAGENAME"

# Распаковка исходников (Ищем файл STAGENAME*.tar.xz)
# Мы используем поиск по маске в смонтированном кэше
DL_CACHE_PATTERN="/root/.cache/downloads/${STAGENAME}*.tar.xz"
# Берем первый найденный файл
REAL_CACHE=$(ls $DL_CACHE_PATTERN 2>/dev/null | head -n 1)

if [[ -f "$REAL_CACHE" ]]; then
    echo "Unpacking cache: $REAL_CACHE"
    tar xaf "$REAL_CACHE" -C .
else
    echo "Warning: No source cache found for $STAGENAME at $DL_CACHE_PATTERN"
    ls -l .cache/downloads
    # Если это критический этап (как mingw), билд упадет дальше сам
fi

# Настройка флагов
export RAW_CFLAGS="$CFLAGS"
export RAW_CXXFLAGS="$CXXFLAGS"
export RAW_LDFLAGS="$LDFLAGS"
export RAW_LDEXEFLAGS="$LDEXEFLAGS"
[[ -n "$STAGE_CFLAGS" ]] && export CFLAGS="$CFLAGS $STAGE_CFLAGS"
[[ -n "$STAGE_CXXFLAGS" ]] && export CXXFLAGS="$CXXFLAGS $STAGE_CXXFLAGS"
[[ -n "$STAGE_LDFLAGS" ]] && export LDFLAGS="$LDFLAGS $STAGE_LDFLAGS"
[[ -n "$STAGE_LDEXEFLAGS" ]] && export LDEXEFLAGS="$LDEXEFLAGS $STAGE_LDEXEFLAGS"

# Загрузка и выполнение
source "$SCRIPT_PATH"

if [[ -z "$2" ]]; then
    ffbuild_dockerbuild
else
    "$2"
fi

# Очистка
cd /
rm -rf "/build/$STAGENAME"
