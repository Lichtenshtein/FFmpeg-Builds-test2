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

# Начало группы в логах GitHub
echo "::group::$STAGENAME"

if [[ "$SCRIPT_SKIP" != "1" ]]; then
    log_debug "--- DEBUG: Searching source for $STAGENAME ---"
    
    # Сначала ищем по точному симлинку (быстрый путь)
    if [[ -L "${CACHE_DIR}/${STAGENAME}.tar.zst" ]]; then
        REAL_CACHE=$(readlink -f "${CACHE_DIR}/${STAGENAME}.tar.zst")
        log_info "Found symlink: ${STAGENAME}.tar.zst -> $REAL_CACHE"
    # Если симлинка нет, ищем любой файл, начинающийся с имени стейджа (для надежности)
    else
        log_warn "No symlink found. Searching by glob: ${STAGENAME}_*.tar.zst"
        REAL_CACHE=$(find "$CACHE_DIR" -name "${STAGENAME}_*.tar.zst" -type f | sort -r | head -n 1)
    fi

    if [[ -n "$REAL_CACHE" && -f "$REAL_CACHE" ]]; then
        log_info "Unpacking $STAGENAME from $REAL_CACHE (Size: $(du -h "$REAL_CACHE" | cut -f1))"
        # tar автоматически вызовет zstd, если он установлен в системе
        tar -I 'zstd -d -T0' -xaf "$REAL_CACHE" -C . --strip-components=0
        
        # Проверка структуры после распаковки
        if [[ $(ls -1 | wc -l) -eq 0 ]]; then
            log_error "ERROR: Archive $REAL_CACHE is empty!"
            exit 1
        fi

        if [[ $(ls -1 | wc -l) -eq 1 && -d $(ls -1) ]]; then
            SUBDIR=$(ls -1)
            log_info "Entering subdirectory: $SUBDIR"
            cd "$SUBDIR"
            log_debug "DEBUG: Current build directory: $(pwd)"
            # позволит сразу понять в логах GitHub, правильно ли распаковался исходник.
            ls -F
        fi
    else
        # Если загрузка была предусмотрена (ffbuild_dockerdl не пуст), но файла нет
        DL_CHECK=$(ffbuild_dockerdl)
        if [[ -n "$DL_CHECK" ]]; then
            log_error "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
            log_error "CRITICAL ERROR: Source cache NOT FOUND for $STAGENAME"
            log_error "Expected: ${CACHE_DIR}/${STAGENAME}.tar.xz"
            log_error "Available files in cache:"
            ls -lh "$CACHE_DIR" | grep "$STAGENAME" || log_debug "No files matching $STAGENAME found at all."
            log_error "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
            exit 1
        fi
        log_info "No source archive required for $STAGENAME (meta-package)."
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

# Конец группы в логах GitHub
echo "::endgroup::"

log_info "################################################################################"
log_info "### STARTING STAGE: $STAGENAME"
log_info "### DATE: $(date)"
log_info "### Starting build function: $build_cmd"
log_info "################################################################################"

if ! $build_cmd; then
    echo "::error file=$SCRIPT_PATH::Build failed for $STAGENAME"
    log_error "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    log_error "!!! ERROR: Build failed for $STAGENAME"
    log_error "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    
    # Выводим текущую директорию и структуру файлов, чтобы понять, где мы
    log_debug "Current directory: $(pwd)"
    
    # Используем 'find' для поиска любых логов ошибок рекурсивно
    # Это найдет логи, даже если они в build/meson-logs или глубоко в CMakeFiles
    LOG_FILES=$(find . -maxdepth 4 -name "config.log" -o -name "meson-log.txt" -o -name "CMakeError.log" -o -name "CMakeOutput.log")

    if [[ -n "$LOG_FILES" ]]; then
        for logfile in $LOG_FILES; do
            echo " "
            log_debug "--- CONTENT OF $logfile (last 150 lines) ---"
            tail -n 150 "$logfile"
            log_debug "--- END OF $logfile ---"
            echo " "
        done
    else
        log_warn "No standard build logs found. Listing all files in current directory to debug:"
        ls -R
    fi
    
    exit 1
fi

# Автоматическая синхронизация префиксов после успешной сборки
# Каждый скрипт в scripts.d обязан устанавливать файлы (make install) в путь, начинающийся с $FFBUILD_DESTDIR$FFBUILD_PREFIX (обычно это /opt/ffdest/opt/ffbuild), иначе система не увидит установленную библиотеку для следующего этапа.
if [[ -d "$FFBUILD_DESTDIR$FFBUILD_PREFIX" ]]; then
    log_info "################################################################"
    log_info "===> SYNCING STAGE: $STAGENAME"
    
    # Проверяем, не пуста ли папка перед синхронизацией
    if [ "$(ls -A "$FFBUILD_DESTDIR$FFBUILD_PREFIX")" ]; then
        log_debug "Source: $FFBUILD_DESTDIR$FFBUILD_PREFIX"
        log_debug "Target: $FFBUILD_PREFIX"

        # rsync опции:
        # -a: архивный режим (сохраняет симлинки, права, даты)
        # -v: подробный вывод (покажет каждый файл в логе)
        # --ignore-existing: можно убрать, если нужно обновлять либы
        if rsync -av "$FFBUILD_DESTDIR$FFBUILD_PREFIX/" "$FFBUILD_PREFIX/"; then
            log_info "${GREEN}${CHECK_MARK} Sync completed successfully.${NC}"
            
            # Расширенный лог: показывает, что именно добавилось (первые 10 файлов для краткости)
            log_debug "New files in prefix (top 10):"
            ls -R "$FFBUILD_PREFIX" | head -n 10
        else
            log_error "${CROSS_MARK} Rsync failed for $STAGENAME!"
            exit 1
        fi
    else
        log_warn "Stage $STAGENAME finished but produced NO files in $FFBUILD_DESTDIR$FFBUILD_PREFIX"
    fi
    log_info "################################################################"
fi

# Вывод статистики в конце каждой стадии (опционально)
# Это покажет Hit Rate прямо в логах GitHub
log_info "--- CCACHE STATISTICS ---"
ccache -s

# Очистка
cd /
rm -rf "/build/$STAGENAME"
