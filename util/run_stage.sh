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

if [[ "$SCRIPT_SKIP" != "1" ]]; then
    echo "--- DEBUG: Searching source for $STAGENAME ---"
    
    # Сначала ищем по точному симлинку (быстрый путь)
    if [[ -L "${CACHE_DIR}/${STAGENAME}.tar.xz" ]]; then
        REAL_CACHE=$(readlink -f "${CACHE_DIR}/${STAGENAME}.tar.xz")
        echo "Found symlink: ${STAGENAME}.tar.xz -> $REAL_CACHE"
    # Если симлинка нет, ищем любой файл, начинающийся с имени стейджа (для надежности)
    else
        echo "No symlink found. Searching by glob: ${STAGENAME}_*.tar.xz"
        REAL_CACHE=$(find "$CACHE_DIR" -name "${STAGENAME}_*.tar.xz" -type f | sort -r | head -n 1)
    fi

    if [[ -n "$REAL_CACHE" && -f "$REAL_CACHE" ]]; then
        echo "Unpacking $STAGENAME from $REAL_CACHE (Size: $(du -h "$REAL_CACHE" | cut -f1))"
        tar xaf "$REAL_CACHE" -C . --strip-components=0
        
        # Проверка структуры после распаковки
        if [[ $(ls -1 | wc -l) -eq 0 ]]; then
            echo "ERROR: Archive $REAL_CACHE is empty!"
            exit 1
        fi

        if [[ $(ls -1 | wc -l) -eq 1 && -d $(ls -1) ]]; then
            SUBDIR=$(ls -1)
            echo "Entering subdirectory: $SUBDIR"
            cd "$SUBDIR"
            # fix постоянной проблемы 'dubious ownership' (сомнительное владение) в Git
            git config --global --add safe.directory "*"
            echo "DEBUG: Current build directory: $(pwd)"
            # позволит сразу понять в логах GitHub, правильно ли распаковался исходник.
            ls -F
        fi
    else
        # Если загрузка была предусмотрена (ffbuild_dockerdl не пуст), но файла нет
        DL_CHECK=$(ffbuild_dockerdl)
        if [[ -n "$DL_CHECK" ]]; then
            echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
            echo "CRITICAL ERROR: Source cache NOT FOUND for $STAGENAME"
            echo "Expected: ${CACHE_DIR}/${STAGENAME}.tar.xz"
            echo "Available files in cache:"
            ls -lh "$CACHE_DIR" | grep "$STAGENAME" || echo "No files matching $STAGENAME found at all."
            echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
            exit 1
        fi
        echo "No source archive required for $STAGENAME (meta-package)."
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

echo " "
echo "################################################################################"
echo "### STARTING STAGE: $STAGENAME"
echo "### DATE: $(date)"
echo "### Starting build function: $build_cmd"
echo "################################################################################"
echo " "

if ! $build_cmd; then
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "!!! ERROR: Build failed for $STAGENAME"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    
    # Выводим текущую директорию и структуру файлов, чтобы понять, где мы
    echo "Current directory: $(pwd)"
    
    # Используем 'find' для поиска любых логов ошибок рекурсивно
    # Это найдет логи, даже если они в build/meson-logs или глубоко в CMakeFiles
    LOG_FILES=$(find . -maxdepth 4 -name "config.log" -o -name "meson-log.txt" -o -name "CMakeError.log" -o -name "CMakeOutput.log")

    if [[ -n "$LOG_FILES" ]]; then
        for logfile in $LOG_FILES; do
            echo " "
            echo "--- CONTENT OF $logfile (last 150 lines) ---"
            tail -n 150 "$logfile"
            echo "--- END OF $logfile ---"
            echo " "
        done
    else
        echo "No standard build logs found. Listing all files in current directory to debug:"
        ls -R
    fi
    
    exit 1
fi

# Автоматическая синхронизация префиксов после успешной сборки
# Каждый скрипт в scripts.d обязан устанавливать файлы (make install) в путь, начинающийся с $FFBUILD_DESTDIR$FFBUILD_PREFIX (обычно это /opt/ffdest/opt/ffbuild), иначе система не увидит установленную библиотеку для следующего этапа.
if [[ -d "$FFBUILD_DESTDIR$FFBUILD_PREFIX" ]]; then
    echo "===> Syncing $STAGENAME to system prefix..."
    cp -r "$FFBUILD_DESTDIR$FFBUILD_PREFIX"/. "$FFBUILD_PREFIX"/
fi

# Вывод статистики в конце каждой стадии (опционально)
# Это покажет Hit Rate прямо в логах GitHub
echo "--- CCACHE STATISTICS ---"
ccache -s

# Очистка
cd /
rm -rf "/build/$STAGENAME"
