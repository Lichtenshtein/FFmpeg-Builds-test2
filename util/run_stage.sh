#!/bin/bash

set -e

SCRIPT_PATH="$1"

# Сначала убедимся, что путь к скрипту вообще есть
if [[ -z "$SCRIPT_PATH" || ! -f "$SCRIPT_PATH" ]]; then
    echo "ERROR: Usage: run_stage <script_path>" >&2
    exit 1
fi

STAGENAME="$(basename "$SCRIPT_PATH" | sed 's/.sh$//')"

# Подгружаем утилиты, используя абсолютный путь
if ! declare -F log_info >/dev/null; then
    . /builder/util/vars.sh "$TARGET" "$VARIANT" 2>/dev/null \
        || { echo "ERROR: vars.sh failed in run_stage for $TARGET/$VARIANT" >&2; exit 1; }
fi

if ! declare -F default_dl >/dev/null; then
    . /builder/util/dl_functions.sh > /dev/null 2>&1 || true
fi

# Создаем и входим в директорию сборки ДО загрузки скрипта
mkdir -p "/build/$STAGENAME"
cd "/build/$STAGENAME"

ccache -z > /dev/null

# Начало группы в логах GitHub
echo "::group::$STAGENAME"

# Подгружаем скрипт заранее, чтобы проверить SCRIPT_SKIP
# любые $(pwd) или относительные пути внутри скрипта будут указывать на /build/STAGENAME
# Используем абсолютный путь к скрипту, так как мы уже сменили cd
source "$(readlink -f "$SCRIPT_PATH")"

# Проверка на пропуск (теперь переменная SCRIPT_SKIP подгружена в контексте нужной папки)
if [[ "$SCRIPT_SKIP" == "1" ]]; then
    log_info "Skipping stage $STAGENAME as requested by script."
    echo "::endgroup::" # ОБЯЗАТЕЛЬНО закрываем перед выходом
    exit 0
fi

# Очищаем временный приемник файлов, чтобы избежать "паразитного" копирования 
# артефактов из предыдущих слоев Docker (если они попали в кэш слоя)
if [[ -d "$FFBUILD_DESTDIR" ]]; then
    log_debug "${BROOM_MARK} Cleaning up temporary DESTDIR: $FFBUILD_DESTDIR"
    rm -rf "${FFBUILD_DESTDIR:?}"/*
fi
mkdir -p "$FFBUILD_DESTDIR"
mkdir -p "$FFBUILD_DESTPREFIX"

CACHE_DIR="/root/.cache/downloads"
REAL_CACHE=""
CURRENT_HASH=$(get_stage_hash "$SCRIPT_PATH")
TGT_FILE="${CACHE_DIR}/${STAGENAME}_${CURRENT_HASH}.tar.zst"
LATEST_LINK="${CACHE_DIR}/${STAGENAME}.tar.zst"

log_debug "${SEARCH_MARK} Searching source for $STAGENAME"

# Ищем точное совпадение (Имя_Хеш)
if [[ -f "$TGT_FILE" ]]; then
    REAL_CACHE="$TGT_FILE"
    log_info "${CHECK_MARK} Exact cache match found: $(basename "$REAL_CACHE")"
    ln -sf "$(basename "$TGT_FILE")" "$LATEST_LINK"
# Ищем по хешу (если скрипт переименован, например 25-glib2 -> 24-glib2)
else
    EXISTING_BY_HASH=$(find "$CACHE_DIR" -maxdepth 1 -name "*_${CURRENT_HASH}.tar.zst" -print -quit)
    if [[ -n "$EXISTING_BY_HASH" ]]; then
        REAL_CACHE="$EXISTING_BY_HASH"
        log_info "${CHECK_MARK} Found cache with matching hash but different name: $(basename "$REAL_CACHE")"
        ln -sf "$(basename "$REAL_CACHE")" "$LATEST_LINK"
# Откат к последней ссылке (LATEST), если точный хеш не найден
    elif [[ -L "$LATEST_LINK" && -f "$LATEST_LINK" ]]; then
        REAL_CACHE=$(readlink -f "$LATEST_LINK")
        log_warn "${XCLAM_MARK} Exact hash $CURRENT_HASH not found. Falling back to latest symlink: $(basename "$REAL_CACHE")"
    fi
fi

# Проверяем, нужны ли вообще исходники для этой стадии
DL_COMMANDS=$(ffbuild_dockerdl) || {
    log_error "ffbuild_dockerdl failed for $STAGENAME"
    exit 1
}

if [[ -n "$DL_COMMANDS" ]]; then
    # Если кэш не найден ни одним способом
    if [[ -z "$REAL_CACHE" || ! -f "$REAL_CACHE" ]]; then
        log_warn "${XCLAM_MARK} Source cache NOT FOUND for $STAGENAME. Attempting direct download..."
        log_debug "Expected hash: $CURRENT_HASH | Target file: $TGT_FILE"

        # Пытаемся скачать исходники "на лету"
        if eval "$DL_COMMANDS"; then
            log_info "${CHECK_MARK} Direct download successful for $STAGENAME."
            # Очистка перед сохранением в кэш
            if [[ -d ".git" ]]; then
                log_debug "${BROOM_MARK} Running git clean -fdx for $STAGENAME..."
                git clean -fdx
            fi
            # Сразу создаем архив в кэше, чтобы в следующий раз он подхватился мгновенно
            log_info "${ARCH_MARK} Creating new cache archive for $STAGENAME..."
            tar -I 'zstd -T0 -3' -cf "$TGT_FILE" .
            ln -sf "$(basename "$TGT_FILE")" "$LATEST_LINK"
        else
            # блок ошибки, срабатывает только загрузка провалилась.
            log_error "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
            log_error "${CROSS_MARK} ERROR: No source cache and download failed for $STAGENAME"
            log_error "Expected hash: $CURRENT_HASH"
            log_error "Available files in cache for this component:"
            ls -lh "$CACHE_DIR" | grep "$STAGENAME" || log_debug "No files matching $STAGENAME found."
            log_error "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
            exit 1
        fi
    else
        # Если REAL_CACHE был найден (одним из 3-х способов выше)
        log_info "${EXTR_MARK} Unpacking $STAGENAME from $REAL_CACHE..."
        tar -I 'zstd -d -T0' -xaf "$REAL_CACHE" -C .
    fi

    # Поиск корня проекта (если архив распаковался в подпапку)
    if [[ ! -f "Configure" && ! -f "configure" && ! -f "CMakeLists.txt" && ! -f "meson.build" ]]; then
        log_warn "${XCLAM_MARK} No build file in root. ${SEARCH_MARK} Searching one level deeper..."
        CANDIDATE=$(find . -maxdepth 2 \( -name "Configure" -o -name "configure" -o -name "CMakeLists.txt" -o -name "meson.build" \) -printf '%h\n' | head -n 1)
        if [[ -n "$CANDIDATE" ]]; then
            log_info "${DIRS_MARK} Project root found at $CANDIDATE. Entering..."
            cd "$CANDIDATE"
        fi
    fi

    # Проверка, что после всех манипуляций папка не пуста
    if [[ $(ls -A | wc -l) -eq 0 ]]; then
        log_error "${CROSS_MARK} ERROR: Build directory is empty after unpacking/downloading $STAGENAME!"
        exit 1
    fi
    
    log_debug "${DIRS_MARK} Final build directory: $(pwd)"
    ls -F | head -n 5
else
    log_info "No source archive required for $STAGENAME (meta-package)."
fi

# Запоминаем "чистые" системные флаги из vars.sh ОДИН РАЗ.
# Если они уже были сохранены ранее, не трогаем их.
if [[ -z "$RAW_CFLAGS" ]]; then
    export RAW_CFLAGS="$CFLAGS"
    export RAW_CPPFLAGS="$CPPFLAGS"
    export RAW_CXXFLAGS="$CXXFLAGS"
    export RAW_LDFLAGS="$LDFLAGS"
fi
# Формируем флаги ТОЛЬКО для этой конкретной стадии.
# берем системную базу и добавляем к ней специфичные флаги стадии.
# НЕ экспортируем их обратно в глобальные RAW_ переменные.
export CFLAGS="$(echo $RAW_CFLAGS $STAGE_CFLAGS | xargs)"
# Аналогично для CPPFLAGS (часто пусты)
export CPPFLAGS="$(echo ${CPPFLAGS} $STAGE_CPPFLAGS | xargs)"
export CXXFLAGS="$(echo $RAW_CXXFLAGS $STAGE_CXXFLAGS | xargs)"
export LDFLAGS="$(echo $RAW_LDFLAGS $STAGE_LDFLAGS | xargs)"

log_debug "${STAGENAME}-specific CFLAGS: $CFLAGS"

# Выполняем сборку ОДИН РАЗ с проверкой статуса
build_cmd="ffbuild_dockerbuild"
[[ -n "$2" ]] && build_cmd="$2"

log_info "################################################################"
log_info "### ${START_MARK} ${LOG_INFO}STARTING STAGE: $STAGENAME${NC}"
log_info "### DATE: $(date)"
log_info "### Starting build function: $build_cmd"
log_info "################################################################"

if [[ "$FFBUILD_VERBOSE" == "1" ]]; then
    log_info "Verbose mode active. Build output will be shown in real-time."
    if ! ( set -e -o pipefail; wine_run_wrapped $build_cmd ); then
        log_error "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        log_error "!!! ${CROSS_MARK} ERROR: Build failed for ${STAGENAME}"
        log_error "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        log_debug "${BUILD_MARK} Current stage file: ${SCRIPT_PATH}"
        # Выводим текущую директорию и структуру файлов, чтобы понять, где мы
        log_debug "${DIRS_MARK} Current directory: $(pwd)"
        # Используем 'find' для поиска любых логов ошибок рекурсивно
        # Это найдет логи, даже если они в build/meson-logs или глубоко в CMakeFiles
        LOG_FILES=$(find . -maxdepth 4 \( -name "config.log" -o -name "meson-log.txt" -o -name "CMakeError.log" -o -name "CMakeOutput.log" \))
        if [[ -n "$LOG_FILES" ]]; then
            for logfile in $LOG_FILES; do
                log_debug "${LOGS_MARK} ▼ CONTENT OF $logfile (last 300 lines) ▼"
                tail -n 300 "$logfile"
                log_debug "${LOGS_MARK} ▲ END OF $logfile ▲"
            done
        else
            log_warn "${DIRS_MARK} No logs found. Listing all files in current directory:"
            ls -R
        fi
        exit 1
    fi
else
    # Тихий режим: вывод лога только в случае падения
    log_info "Quiet mode active. Output is redirected to /tmp/stage_build.log"
    if ! ( set -e -o pipefail; wine_run_wrapped $build_cmd > /tmp/stage_build.log 2>&1 ); then
        log_error "${CROSS_MARK} Build failed!"
        log_debug "${LOGS_MARK} ▼ DUMPING build log ▼"
        cat /tmp/stage_build.log
        log_debug "${LOGS_MARK} ▲ END OF LOG DUMP ▲"
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
        DELETED_FILES=$(find "$FFBUILD_DESTDIR$FFBUILD_PREFIX" -type f \( -name "*.dll" -o -name "*.dll.a" \) -print)
        if [[ -n "$DELETED_FILES" ]]; then
            log_info "################################################################"
            log_debug "${BROOM_MARK} Cleaning unwanted dynamic DLLs from static stage: $STAGENAME"
            log_info "$DELETED_FILES" | sed "s|$FFBUILD_DESTDIR||g"
            # find "$FFBUILD_DESTDIR$FFBUILD_PREFIX" -type f -name "*.dll" -delete || true
            find "$FFBUILD_DESTDIR$FFBUILD_PREFIX" -type f \( -name "*.dll" -o -name "*.dll.a" \) -delete || true
        fi
    else
        log_debug "${DIRS_MARK} No standard prefix directory to clean for $STAGENAME"
    fi
else
    log_info "${LOCK_MARK} Preserving DLLs for dynamic stage: $STAGENAME"
fi

# Вывод статистики в конце каждой стадии
# Это покажет Hit Rate прямо в логах GitHub
log_info "################################################################"
log_info "${CACHE_MARK} CCACHE STATISTICS:"
ccache -s

# Автоматическая синхронизация префиксов после успешной сборки
# Каждый скрипт в scripts.d обязан устанавливать файлы (make install) в путь, начинающийся с $FFBUILD_DESTDIR$FFBUILD_PREFIX (обычно это /opt/ffdest/opt/ffbuild), иначе система не увидит установленную библиотеку для следующего этапа.
if [[ -d "$FFBUILD_DESTDIR$FFBUILD_PREFIX" ]]; then
    log_info "################################################################"
    log_info "${SYNC_MARK} POST-BUILD AUDIT: $STAGENAME"

    # Identify what was actually built
    mapfile -t NEW_FILES < <(find "$FFBUILD_DESTDIR$FFBUILD_PREFIX" -type f -o -type l)

    if [[ ${#NEW_FILES[@]} -gt 0 ]]; then
        log_info "${DIRS_MARK} Installed ${#NEW_FILES[@]} files to prefix:"
        # Print the list, stripping the long DESTDIR prefix for readability
        printf "%s\n" "${NEW_FILES[@]#$FFBUILD_DESTDIR}" | head -n 50
        [[ ${#NEW_FILES[@]} -gt 50 ]] && echo "  ... (and $((${#NEW_FILES[@]} - 50)) more)"

        # Sync to the PERSISTENT CACHE MOUNT (So the next script sees them)
        # Using -u (update) to avoid overwriting newer files if layers run out of order
        rsync -a --checksum "$FFBUILD_DESTDIR$FFBUILD_PREFIX/" "$FFBUILD_PREFIX/"
        log_info "${CHECK_MARK} Sync completed. Component is now available for dependencies."

        # .la files, dependancies and .pc files auditing
        # if [[ "$SKIP_POST_PATCH" != "1" ]]; then
            # patch_pc_files
        # fi
        # if [[ "$SKIP_POST_CLEAN" != "1" ]]; then
            # clean_la_files
        # fi
        # if [[ "$SKIP_POST_AUDIT" != "1" ]]; then
            # get_deps_list
        # fi
    else
        log_warn "${XCLAM_MARK} Stage $STAGENAME finished but no files were found in DESTDIR."
    fi
    log_info "################################################################"
fi

# Сохраняем переменные для текущего слоя в файл 
VARS_DIR="$FFBUILD_PREFIX/config_parts"
mkdir -p "$VARS_DIR"

log_info "Saving build variables for $STAGENAME..."

# Вспомогательная функция очистки мусора (внутри Docker она работает корректно)
# Удаляем ANSI цвета
# Удаляем переносы строк (заменяем на пробел)
# xargs схлопнет лишние пробелы в одну строку
clean_val() {
    echo "$*" | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g" | tr '\n' ' ' | xargs
}
export -f clean_val

# автосбор из pkg-config (он уже работает и наполняет переменные через export)
if [[ -d "$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig" ]]; then
    log_info "Auto-collecting flags from pkg-config..."
    OLD_PKG_CONFIG_LIBDIR="$PKG_CONFIG_LIBDIR"
    export PKG_CONFIG_LIBDIR="$FFBUILD_DESTDIR$FFBUILD_PREFIX/lib/pkgconfig"
    for pc in "$PKG_CONFIG_LIBDIR"/*.pc; do
        [[ -e "$pc" ]] || continue
        pc_name=$(basename "$pc" .pc)
        # Все флаги компиляции (-I, -D) забираем через --cflags
        _pc_cflags=$(pkg-config --cflags "$pc_name" 2>/dev/null || true)
        [[ -n "$_pc_cflags" ]] && FF_CFLAGS="$FF_CFLAGS $_pc_cflags"
        # Все библиотеки (-l, -L) забираем через --libs --static
        _pc_libs=$(pkg-config --libs --static "$pc_name" 2>/dev/null || true)
        [[ -n "$_pc_libs" ]] && FF_LIBS="$FF_LIBS $_pc_libs"
    done
    export PKG_CONFIG_LIBDIR="$OLD_PKG_CONFIG_LIBDIR"
fi

# Захват ручных echo из функций скрипта (без subshell для ffbuild_ аккумуляторов)
_raw_conf="$(ffbuild_configure 2>/dev/null || true)"
[[ -n "$_raw_conf" ]] && FF_CONFIGURE="$FF_CONFIGURE $_raw_conf"
_raw_cflags="$(ffbuild_cflags 2>/dev/null || true)"
[[ -n "$_raw_cflags" ]] && FF_CFLAGS="$FF_CFLAGS $_raw_cflags"
_raw_cppflags="$(ffbuild_cppflags 2>/dev/null || true)"
[[ -n "$_raw_cppflags" ]] && FF_CPPFLAGS="$FF_CPPFLAGS $_raw_cppflags"
_raw_cxxflags="$(ffbuild_cxxflags 2>/dev/null || true)"
[[ -n "$_raw_cxxflags" ]] && FF_CXXFLAGS="$FF_CXXFLAGS $_raw_cxxflags"
_raw_ldflags="$(ffbuild_ldflags 2>/dev/null || true)"
[[ -n "$_raw_ldflags" ]] && FF_LDFLAGS="$FF_LDFLAGS $_raw_ldflags"
_raw_libs="$(ffbuild_libs 2>/dev/null || true)"
[[ -n "$_raw_libs" ]] && FF_LIBS="$FF_LIBS $_raw_libs"

# экспорт накопленного результата для printf
export FF_CONFIGURE FF_CFLAGS FF_LIBS FF_CXXFLAGS FF_LDFLAGS FF_CPPFLAGS

# Если в этой строке в логе пустота, значит, проблема выше, в самом скрипте компонента (например, в 18-zlib.sh), который не вызывает ffbuild_cflags
[[ -n "$_raw_conf" ]] && log_debug "FINAL FF_CONFIGURE: $FF_CONFIGURE"
[[ -n "$_raw_cflags" ]] && log_debug "FINAL FF_CFLAGS: $FF_CFLAGS"
[[ -n "$_raw_cppflags" ]] && log_debug "FINAL FF_CPPFLAGS: $FF_CPPFLAGS"
[[ -n "$_raw_cxxflags" ]] && log_debug "FINAL FF_CXXFLAGS: $FF_CXXFLAGS"
[[ -n "$_raw_ldflags" ]]  && log_debug "FINAL FF_LDFLAGS: $FF_LDFLAGS"
[[ -n "$_raw_libs" ]] && log_debug "FINAL FF_LIBS: $FF_LIBS"

# Сохраняем в .vars файл с защитой кавычками только те переменные, которые были реально установлены в скрипте компонента (текущий блок printf)
{
    [[ -n "$FF_CONFIGURE" ]]  && printf "export FF_CONFIGURE+=' %s'\n" "$(clean_val "$FF_CONFIGURE")"
    [[ -n "$FF_CFLAGS" ]]     && printf "export FF_CFLAGS+=' %s'\n"    "$(clean_val "$FF_CFLAGS")"
    [[ -n "$FF_CXXFLAGS" ]]   && printf "export FF_CXXFLAGS+=' %s'\n"  "$(clean_val "$FF_CXXFLAGS")"
    [[ -n "$FF_CPPFLAGS" ]]   && printf "export FF_CPPFLAGS+=' %s'\n"  "$(clean_val "$FF_CPPFLAGS")"
    [[ -n "$FF_LDFLAGS" ]]    && printf "export FF_LDFLAGS+=' %s'\n"   "$(clean_val "$FF_LDFLAGS")"
    [[ -n "$FF_LIBS" ]]       && printf "export FF_LIBS+=' %s'\n"      "$(clean_val "$FF_LIBS")"
} > "$VARS_DIR/${STAGENAME}.vars"

# Диагностика созданных файлов
log_debug "Current files in $VARS_DIR:"
ls -1 "$VARS_DIR" | grep ".vars" || log_warn "No .vars files created in this stage."
log_info "################################################################"

# Очистка
trap 'echo "::endgroup::"; cd /; rm -rf "/build/$STAGENAME"' EXIT
exit 0