#!/bin/bash
set -e

SCRIPT_PATH="$1"
STAGENAME="$(basename "$SCRIPT_PATH" | sed 's/.sh$//')"

# Подгружаем скрипт заранее, чтобы проверить SCRIPT_SKIP
source "$SCRIPT_PATH"

mkdir -p "/build/$STAGENAME"
cd "/build/$STAGENAME"

CACHE_DIR="/root/.cache/downloads"
REAL_CACHE=""

# Если скрипт НЕ помечен как SKIP, ищем для него исходники
if [[ "$SCRIPT_SKIP" != "1" ]]; then
    if [[ -f "${CACHE_DIR}/${STAGENAME}.tar.xz" ]]; then
        REAL_CACHE="${CACHE_DIR}/${STAGENAME}.tar.xz"
    else
        # Ищем по маске, если симлинк не создался
        REAL_CACHE=$(find "$CACHE_DIR" -name "${STAGENAME}_*.tar.xz" | head -n 1)
    fi

    if [[ -n "$REAL_CACHE" && -f "$REAL_CACHE" ]]; then
        echo "Unpacking $STAGENAME from $REAL_CACHE"
        tar xaf "$REAL_CACHE" -C . --strip-components=0
        # Если после распаковки в директории всего одна папка — заходим в неё
        if [[ $(ls -1 | wc -l) -eq 1 && -d $(ls -1) ]]; then
            SUBDIR=$(ls -1)
            echo "Moving into subdirectory: $SUBDIR"
            cd "$SUBDIR"
        fi
    else
        # Если загрузка была предусмотрена (ffbuild_dockerdl не пуст), но файла нет - это ошибка
        DL_CHECK=$(ffbuild_dockerdl)
        if [[ -n "$DL_CHECK" ]]; then
            echo "ERROR: Source cache NOT FOUND for $STAGENAME"
            echo "Full content of $CACHE_DIR:"
            ls -F "$CACHE_DIR"
            # ПАДАЕМ СРАЗУ, чтобы не гадать по ошибке cp
            exit 1
        fi
        echo "No source archive for $STAGENAME (meta-package), continuing..."
    fi
fi

# Применяем флаги
export RAW_CFLAGS="$CFLAGS"
export RAW_CXXFLAGS="$CXXFLAGS"
export RAW_LDFLAGS="$LDFLAGS"
export RAW_LDEXEFLAGS="$LDEXEFLAGS"
[[ -n "$STAGE_CFLAGS" ]] && export CFLAGS="$CFLAGS $STAGE_CFLAGS"
[[ -n "$STAGE_CXXFLAGS" ]] && export CXXFLAGS="$CXXFLAGS $STAGE_CXXFLAGS"
[[ -n "$STAGE_LDFLAGS" ]] && export LDFLAGS="$LDFLAGS $STAGE_LDFLAGS"
[[ -n "$STAGE_LDEXEFLAGS" ]] && export LDEXEFLAGS="$LDEXEFLAGS $STAGE_LDEXEFLAGS"

# Выполняем сборку ОДИН РАЗ с проверкой статуса
build_cmd="ffbuild_dockerbuild"
[[ -n "$2" ]] && build_cmd="$2"

echo "===> Starting build function: $build_cmd"

if ! $build_cmd; then
    echo "ERROR: Build failed for $STAGENAME"
    # Пытаемся найти логи ошибок (для Autotools или CMake)
    if [[ -f "config.log" ]]; then
        cat config.log
    elif [[ -f "build/CMakeFiles/CMakeError.log" ]]; then
        cat build/CMakeFiles/CMakeError.log
    fi
    exit 1
fi

# Очистка
cd /
rm -rf "/build/$STAGENAME"
