#!/bin/bash
set -e

SCRIPT_PATH="$1"
STAGENAME="$(basename "$SCRIPT_PATH" | sed 's/.sh$//')"

# Подготовка папки сборки
mkdir -p "/build/$STAGENAME"
cd "/build/$STAGENAME"

# Поиск кэша
# Проверяем два варианта: с хэшем и чистый симлинк
CACHE_DIR="/root/.cache/downloads"
REAL_CACHE=""

# DL_CACHE_PATTERN="/root/.cache/downloads/${STAGENAME}*.tar.xz"
# REAL_CACHE=$(ls $DL_CACHE_PATTERN 2>/dev/null | head -n 1)

if [[ -f "${CACHE_DIR}/${STAGENAME}.tar.xz" ]]; then
    REAL_CACHE="${CACHE_DIR}/${STAGENAME}.tar.xz"
else
    # Ищем по маске, если симлинк не создался
    REAL_CACHE=$(find "$CACHE_DIR" -name "${STAGENAME}_*.tar.xz" | head -n 1)
fi

if [[ -n "$REAL_CACHE" && -f "$REAL_CACHE" ]]; then
    echo "Found cache for $STAGENAME: $REAL_CACHE"
    tar xaf "$REAL_CACHE" -C . --strip-components=0
else
    echo "ERROR: Source cache NOT FOUND for $STAGENAME"
    echo "Looked for: ${CACHE_DIR}/${STAGENAME}.tar.xz or ${STAGENAME}_*.tar.xz"
    # Выведем список похожих файлов для отладки
    echo "Available files for this prefix:"
    ls -l "$CACHE_DIR" | grep "^.* ${STAGENAME}" || echo "No files starting with $STAGENAME"
    exit 1 # ПАДАЕМ СРАЗУ, чтобы не гадать по ошибке cp
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
