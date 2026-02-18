#!/bin/bash
set -e

SCRIPT_PATH="$1"
STAGENAME="$(basename "$SCRIPT_PATH" | sed 's/.sh$//')"

# Подгружаем утилиты, используя абсолютный путь
if ! declare -F log_info >/dev/null; then
    . /builder/util/vars.sh "$TARGET" "$VARIANT" > /dev/null 2>&1 || true
fi

if ! declare -F default_dl >/dev/null; then
    . /builder/util/dl_functions.sh > /dev/null 2>&1 || true
fi

# Создаем и входим в директорию сборки ДО загрузки скрипта
mkdir -p "/build/$STAGENAME"
cd "/build/$STAGENAME"

# Подгружаем скрипт заранее, чтобы проверить SCRIPT_SKIP
# любые $(pwd) или относительные пути внутри скрипта будут указывать на /build/STAGENAME
# Используем абсолютный путь к скрипту, так как мы уже сменили cd
source "$(readlink -f "$SCRIPT_PATH")"

# Начало группы в логах GitHub
echo "::group::$STAGENAME"

# Проверка на пропуск (теперь переменная SCRIPT_SKIP подгружена в контексте нужной папки)
if [[ "$SCRIPT_SKIP" == "1" ]]; then
    log_info "Skipping stage $STAGENAME as requested by script."
    echo "::endgroup::" # ОБЯЗАТЕЛЬНО закрываем перед выходом
    exit 0
fi

# Очищаем временный приемник файлов, чтобы избежать "паразитного" копирования 
# артефактов из предыдущих слоев Docker (если они попали в кэш слоя)
if [[ -d "$FFBUILD_DESTDIR" ]]; then
    log_debug "Cleaning up temporary DESTDIR: $FFBUILD_DESTDIR"
    rm -rf "${FFBUILD_DESTDIR:?}"/*
fi
mkdir -p "$FFBUILD_DESTDIR"

CACHE_DIR="/root/.cache/downloads"
REAL_CACHE=""

ccache -z

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

        # Распаковываем без лишних флагов --strip-components
        tar -I 'zstd -d -T0' -xaf "$REAL_CACHE" -C .
        
        # Пытаемся найти корень проекта, только если в текущей папке пусто
        if [[ ! -f "meson.build" && ! -f "configure" && ! -f "CMakeLists.txt" ]]; then
            log_warn "No build file in root. Searching one level deeper..."
            # Ищем строго на 1 уровень глубже (maxdepth 2)
            CANDIDATE=$(find . -maxdepth 2 \( -name "meson.build" -o -name "configure" -o -name "CMakeLists.txt" \) -printf '%h\n' | head -n 1)
            if [[ -n "$CANDIDATE" ]]; then
                log_info "Project root found at $CANDIDATE. Entering..."
                cd "$CANDIDATE"
            fi
        fi

        # Финальная проверка не пуста ли папка после распаковки
        if [[ $(ls -A | wc -l) -eq 0 ]]; then
            log_error "ERROR: Archive $REAL_CACHE is empty or failed to unpack!"
            exit 1
        fi
        
        log_debug "Final build directory: $(pwd)"
        ls -F | head -n 5
    else
        # Если загрузка была предусмотрена (ffbuild_dockerdl не пуст), но файла нет
        DL_CHECK=$(ffbuild_dockerdl)
        if [[ -n "$DL_CHECK" ]]; then
            log_error "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
            log_error "CRITICAL ${RED}ERROR${NC}: Source cache NOT FOUND for $STAGENAME"
            log_error "Expected: ${CACHE_DIR}/${STAGENAME}.tar.zst"
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

log_info "################################################################################"
log_info "### STARTING STAGE: $STAGENAME"
log_info "### DATE: $(date)"
log_info "### Starting build function: $build_cmd"
log_info "################################################################################"

if [[ "$FFBUILD_VERBOSE" == "1" ]]; then
    log_info "Verbose mode active. Build output will be shown in real-time."
    if ! $build_cmd; then
        echo "::error file=$SCRIPT_PATH::Build failed for $STAGENAME"
        log_error "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        log_error "!!! ${RED}ERROR${NC}: Build failed for $STAGENAME"
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
else
    # Тихий режим с дампом лога только при ошибке
    if ! $build_cmd > /tmp/stage_build.log 2>&1; then
        cat /tmp/stage_build.log
        exit 1
    fi
fi

# Список стадий, которым РАЗРЕШЕНО иметь DLL (ИИ, драйверы, системные компоненты)
# Очистка динамических библиотек для каждого статического скрипта с белым списком
PRESERVE_DLL_PATTERN="${DLL_PRESERVE_LIST:-openvino|torch|tensorflow|vulkan|amf|nvcodec|mfx|onevpl}"
if [[ ! "$STAGENAME" =~ $PRESERVE_DLL_PATTERN ]]; then
    if [[ -d "$FFBUILD_DESTDIR$FFBUILD_PREFIX" ]]; then
        log_debug "Cleaning unwanted DLLs from static stage: $STAGENAME"
        find "$FFBUILD_DESTDIR$FFBUILD_PREFIX" -type f \( -name "*.dll" -o -name "*.dll.a" \) -delete || true
    else
        log_debug "No standard prefix directory to clean for $STAGENAME"
    fi
else
    log_info "Preserving DLLs for dynamic stage: $STAGENAME"
fi

# Автоматическая синхронизация префиксов после успешной сборки
# Каждый скрипт в scripts.d обязан устанавливать файлы (make install) в путь, начинающийся с $FFBUILD_DESTDIR$FFBUILD_PREFIX (обычно это /opt/ffdest/opt/ffbuild), иначе система не увидит установленную библиотеку для следующего этапа.
if [[ -d "$FFBUILD_DESTDIR$FFBUILD_PREFIX" ]]; then
    log_info "################################################################"
    log_info "===> SYNCING STAGE: $STAGENAME"
    
    # Проверяем наличие файлов (игнорируя пустые директории)
    if [[ -n $(find "$FFBUILD_DESTDIR$FFBUILD_PREFIX" -type f -print -quit) ]]; then
        log_debug "Source: $FFBUILD_DESTDIR$FFBUILD_PREFIX"
        log_debug "Target: $FFBUILD_PREFIX"

        # Продвинутые флаги rsync:
        # -a: архив (права, даты, симлинки)
        # -v: подробный лог (поможет увидеть, ЧТО именно установила либа)
        # --update: НЕ перезаписывать файлы в таргете, если они новее
        # --ignore-times: но если размер/дата отличаются - обновить
        # --ignore-existing: можно убрать, если нужно обновлять либы
        if rsync -av --update "$FFBUILD_DESTDIR$FFBUILD_PREFIX/" "$FFBUILD_PREFIX/"; then
            log_info "${GREEN}${CHECK_MARK} Sync completed. Artifacts moved to global prefix.${NC}"
            # Расширенный лог: показывает, что именно добавилось (первые 10 файлов для краткости)
            log_debug "New files in prefix (top 10):"
            ls -R "$FFBUILD_PREFIX" | head -n 10
        else
            log_error "${CROSS_MARK} Sync failed for $STAGENAME!"
            exit 1
        fi
        
        # Очищаем DESTDIR сразу после копирования, 
        # чтобы освободить место в текущем слое Docker перед финализацией
        rm -rf "${FFBUILD_DESTDIR:?}"/*
    else
        log_warn "Stage $STAGENAME finished but $FFBUILD_DESTDIR$FFBUILD_PREFIX is empty."
    fi
    log_info "################################################################"
fi

# Очистка
cd /
rm -rf "/build/$STAGENAME"

# Конец группы в логах GitHub
echo "::endgroup::"

# Вывод статистики в конце каждой стадии
# Это покажет Hit Rate прямо в логах GitHub
log_info "--- CCACHE STATISTICS ---"
ccache -s