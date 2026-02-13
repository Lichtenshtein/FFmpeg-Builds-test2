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
    
    # Ищем логи везде, где они могут быть
    LOG_FOUND=0
    for logfile in "config.log" "../config.log" "build/meson-logs/meson-log.txt" "meson-logs/meson-log.txt" "build/CMakeFiles/CMakeError.log" "CMakeFiles/CMakeError.log"; do
        if [[ -f "$logfile" ]]; then
            echo "--- Found log: $logfile ---"
            tail -n 100 "$logfile"
            LOG_FOUND=1
            break
        fi
    done

    if [[ $LOG_FOUND -eq 0 ]]; then
        echo "No specific build logs found (checked config.log, meson-log, CMakeError.log)."
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
