#!/bin/bash
set -e

SCRIPT_PATH="$1"

# Сначала убедимся, что путь к скрипту вообще есть
if [[ -z "$SCRIPT_PATH" || ! -f "$SCRIPT_PATH" ]]; then
    log_error "Usage: run_stage <script_path>"
    exit 1
fi

STAGENAME="$(basename "$SCRIPT_PATH" | sed 's/.sh$//')"

# Определяем режим работы Wine (берем из ENV или ставим auto по умолчанию)
USE_WINE_VAL="${USE_WINE:-auto}"
# Функция для принятия решения о запуске графического окружения и Wine
should_run_wine() {
    [[ "$USE_WINE_VAL" == "on" ]] && return 0
    [[ "$USE_WINE_VAL" == "off" ]] && return 1
    # Режим 'auto': проверяем наличие команд сборки или явного вызова wine в скрипте
    grep -qE "meson setup|cmake|\./configure|wine" "$SCRIPT_PATH"
}
# Инициализируем Xvfb и Wine ТОЛЬКО если это реально необходимо
if should_run_wine; then
    # Проверка и запуск Xvfb (необходим для работы Wine в headless режиме)
    if ! pgrep -x "Xvfb" > /dev/null; then
        log_info "Starting Xvfb (Display :99) for Wine/Build tests..."
        Xvfb :99 -screen 0 1024x768x16 > /dev/null 2>&1 &
        # Даем немного времени на инициализацию дисплея
        sleep 5
    fi
    # Инициализация префикса Wine, если он еще не создан (drive_c отсутствует)
    if [[ ! -d "$WINEPREFIX/drive_c" ]]; then
        log_info "Initializing Wine Win64 prefix in $WINEPREFIX..."
        # Запускаем wineboot в фоновом режиме, затем ждем завершения сервера
        wine64 wineboot --init > /dev/null 2>&1 && wineserver -w
        log_info "Wine prefix ready."
    fi
else
    log_debug "Stage $STAGENAME: Wine/Xvfb initialization skipped (Mode: $USE_WINE_VAL)."
fi

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

ccache -z > /dev/null

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
CURRENT_HASH=$(get_stage_hash "$SCRIPT_PATH")
TGT_FILE="${CACHE_DIR}/${STAGENAME}_${CURRENT_HASH}.tar.zst"
LATEST_LINK="${CACHE_DIR}/${STAGENAME}.tar.zst"

log_debug "--- DEBUG: Searching source for $STAGENAME ---"

# Ищем точное совпадение (Имя_Хеш)
if [[ -f "$TGT_FILE" ]]; then
    REAL_CACHE="$TGT_FILE"
    log_info "Exact cache match found: $(basename "$REAL_CACHE")"
    ln -sf "$(basename "$TGT_FILE")" "$LATEST_LINK"
    # fix for Docker ro filesystem
    # ln -sf "$(basename "$TGT_FILE")" "$LATEST_LINK" 2>/dev/null || true
# Ищем по хешу (если скрипт переименован, например 25-glib2 -> 24-glib2)
else
    EXISTING_BY_HASH=$(find "$CACHE_DIR" -maxdepth 1 -name "*_${CURRENT_HASH}.tar.zst" -print -quit)
    if [[ -n "$EXISTING_BY_HASH" ]]; then
        REAL_CACHE="$EXISTING_BY_HASH"
        log_info "Found cache with matching hash but different name: $(basename "$REAL_CACHE")"
        ln -sf "$(basename "$REAL_CACHE")" "$LATEST_LINK"
# Откат к последней ссылке (LATEST), если точный хеш не найден
    elif [[ -L "$LATEST_LINK" && -f "$LATEST_LINK" ]]; then
        REAL_CACHE=$(readlink -f "$LATEST_LINK")
        log_warn "Exact hash $CURRENT_HASH not found. Falling back to latest symlink: $(basename "$REAL_CACHE")"
    fi
fi

# Проверяем, нужны ли вообще исходники для этой стадии
DL_COMMANDS=$(ffbuild_dockerdl)

if [[ -n "$DL_COMMANDS" ]]; then
    # Если кэш не найден ни одним способом
    if [[ -z "$REAL_CACHE" || ! -f "$REAL_CACHE" ]]; then
        log_warn "Source cache NOT FOUND for $STAGENAME. Attempting direct download..."
        log_debug "Expected hash: $CURRENT_HASH | Target file: $TGT_FILE"

        # Пытаемся скачать исходники "на лету"
        if eval "$DL_COMMANDS"; then
            log_info "Direct download successful for $STAGENAME."
            # Очистка перед сохранением в кэш
            if [[ -d ".git" ]]; then
                log_debug "Running git clean -fdx for $STAGENAME..."
                git clean -fdx
            fi
            # Сразу создаем архив в кэше, чтобы в следующий раз он подхватился мгновенно
            log_info "Creating new cache archive for $STAGENAME..."
            tar -I 'zstd -T0 -3' -cf "$TGT_FILE" .
            ln -sf "$(basename "$TGT_FILE")" "$LATEST_LINK"
        else
            # блок ошибки, срабатывает только загрузка провалилась.
            log_error "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
            log_error "CRITICAL ERROR: No source cache and download failed for $STAGENAME"
            log_error "Expected hash: $CURRENT_HASH"
            log_error "Available files in cache for this component:"
            ls -lh "$CACHE_DIR" | grep "$STAGENAME" || log_debug "No files matching $STAGENAME found."
            log_error "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
            exit 1
        fi
    else
        # Если REAL_CACHE был найден (одним из 3-х способов выше)
        log_info "Unpacking $STAGENAME from $REAL_CACHE..."
        tar -I 'zstd -d -T0' -xaf "$REAL_CACHE" -C .
    fi

    # Поиск корня проекта (если архив распаковался в подпапку)
    if [[ ! -f "Configure" && ! -f "configure" && ! -f "CMakeLists.txt" && ! -f "meson.build" ]]; then
        log_warn "No build file in root. Searching one level deeper..."
        CANDIDATE=$(find . -maxdepth 2 \( -name "Configure" -o -name "configure" -o -name "CMakeLists.txt" -o -name "meson.build" \) -printf '%h\n' | head -n 1)
        if [[ -n "$CANDIDATE" ]]; then
            log_info "Project root found at $CANDIDATE. Entering..."
            cd "$CANDIDATE"
        fi
    fi

    # Проверка, что после всех манипуляций папка не пуста
    if [[ $(ls -A | wc -l) -eq 0 ]]; then
        log_error "ERROR: Build directory is empty after unpacking/downloading $STAGENAME!"
        exit 1
    fi
    
    log_debug "Final build directory: $(pwd)"
    ls -F | head -n 5
else
    log_info "No source archive required for $STAGENAME (meta-package)."
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

log_info "################################################################"
log_info "### STARTING STAGE: $STAGENAME"
log_info "### DATE: $(date)"
log_info "### Starting build function: $build_cmd"
log_info "################################################################"

if [[ "$FFBUILD_VERBOSE" == "1" ]]; then
    log_info "Verbose mode active. Build output will be shown in real-time."
    if ! ( set -e; $build_cmd ); then
        echo "::error file=$SCRIPT_PATH::Build failed for $STAGENAME"
        log_error "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        log_error "!!! ${RED}ERROR${NC}: Build failed for $STAGENAME"
        log_error "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        # Выводим текущую директорию и структуру файлов, чтобы понять, где мы
        log_debug "Current directory: $(pwd)"
        # Используем 'find' для поиска любых логов ошибок рекурсивно
        # Это найдет логи, даже если они в build/meson-logs или глубоко в CMakeFiles
        LOG_FILES=$(find . -maxdepth 4 -name "config.log" -o -name "meson-log.txt" -o -name "CMakeError.log" -o -name "CMakeOutput.log")
        if [[ -n "$LOG_FILES" ]]; then
            for logfile in $LOG_FILES; do
                echo " "
                log_debug "--- CONTENT OF $logfile (last 150 lines) ---"
                tail -n 1150 "$logfile"
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
    # Тихий режим: вывод лога только в случае падения
    log_info "Quiet mode active. Output is redirected to /tmp/stage_build.log"
    if ! ( set -e; $build_cmd > /tmp/stage_build.log 2>&1 ); then
        log_error "Build failed! Dumping build log:"
        echo "----------------------------------------------------------------"
        cat /tmp/stage_build.log
        echo "----------------------------------------------------------------"
        exit 1
    fi
fi

# Список стадий, которым РАЗРЕШЕНО иметь DLL (ИИ, драйверы, системные компоненты)
# Очистка динамических библиотек для каждого статического скрипта с белым списком
# Библиотеки MinGW создают libимя.dll.a (implib) даже для статики. Удаление всех *.dll.a может быть слишком радикальным
# find "$FFBUILD_DESTDIR$FFBUILD_PREFIX" -type f -name "*.dll" -delete || true
PRESERVE_DLL_PATTERN="${DLL_PRESERVE_LIST:-openvino|torch|tensorflow|vulkan|amf|nvcodec|mfx|onevpl}"
if [[ ! "$STAGENAME" =~ $PRESERVE_DLL_PATTERN ]]; then
    if [[ -d "$FFBUILD_DESTDIR$FFBUILD_PREFIX" ]]; then
        log_info "################################################################"
        log_debug "Cleaning unwanted DLLs from static stage: $STAGENAME"
        find "$FFBUILD_DESTDIR$FFBUILD_PREFIX" -type f \( -name "*.dll" -o -name "*.dll.a" \) -delete || true
    else
        log_debug "No standard prefix directory to clean for $STAGENAME"
    fi
else
    log_info "Preserving DLLs for dynamic stage: $STAGENAME"
fi

# Вывод статистики в конце каждой стадии
# Это покажет Hit Rate прямо в логах GitHub
log_info "################################################################"
log_info "--- CCACHE STATISTICS ---"
ccache -s

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