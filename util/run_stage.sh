#!/bin/bash

set -e

STAGE="$1"

# Сначала убедимся, что путь к скрипту вообще есть
if [[ -z "$STAGE" || ! -f "$STAGE" ]]; then
    echo "ERROR: Usage: run_stage <STAGE>" >&2
    exit 1
fi

# Подгружаем утилиты, используя абсолютный путь
if ! declare -F log_info >/dev/null; then
    . /builder/util/vars.sh "$TARGET" "$VARIANT" 2>/dev/null \
        || { echo "ERROR: vars.sh failed in run_stage for $TARGET/$VARIANT" >&2; exit 1; }
fi

if ! declare -F default_dl >/dev/null; then
    . "$UTIL_DIR"/dl_functions.sh > /dev/null 2>&1 || true
fi

# Обнуляем статистику
ccache -z > /dev/null
# Сбрасываем счетчик секунд в начале этапа
SECONDS=0
STAGE_START_TIME=$(date +%s)
STAGE_LOG="/tmp/stage_build_${STAGENAME}.log"
# Write a timestamp file before $build_cmd runs, then use find -newer to detect which .pc files were created by this build
TIMESTAMP_FILE=$(mktemp)
sleep 1

# Call dynamic STAGE function 
unset STAGE_HASH STAGENAME COMPONENT_NAME STAGE_CACHE_FILE STAGE_LATEST_LINK REAL_CACHE
eval "$(stage_vars "$STAGE")"

# Определяем режим работы Wine (берем из ENV или ставим auto по умолчанию)
# may not work from here because $STAGE is set in run_stage.sh before setup_wine_env is called; might need to be moved to top of run_stage.sh
USE_WINE="${USE_WINE:-1}"
setup_wine_env() {
    # Сохраняем текущее состояние set -e
    local errexit_state=$([[ $- =~ e ]] && echo "set -e" || echo "set +e")
    set +e # Временно отключаем остановку при ошибках

    # Wine globally disabled
    if [[ "${USE_WINE:-0}" != "1" ]]; then
        eval "$errexit_state"; return 0
    fi

    # No stage to inspect
    if [[ -z "$STAGE" || ! -f "$STAGE" ]]; then
        eval "$errexit_state"; return 0
    fi

    # Scan the stage script for patterns that indicate Wine is needed.
    # We search for:
    #   - explicit wine invocations
    #   - test runner calls that require executing Windows binaries
    #   - direct .exe execution
    # NOTE: grep searches the script SOURCE FILE, so patterns must match
    # what authors write in ffbuild_dockerbuild(), not runtime commands.
    local wine_patterns=(
        'wine[[:space:]]'       # wine <binary>
        'wineboot'              # explicit wineboot call
        '\.exe'                 # any .exe reference (run or test)
        'meson[[:space:]]+test' # meson test runner
        'ctest'                 # cmake test runner
        'make[[:space:]]+check' # autotools make check
        'make[[:space:]]+test'  # autotools make test
        'ninja[[:space:]]+test' # ninja test target
    )

    local combined_pattern
    combined_pattern=$(printf '%s|' "${wine_patterns[@]}")
    combined_pattern="${combined_pattern%|}" # strip trailing |

    if ! grep -qE "$combined_pattern" "$STAGE"; then
        log_debug "Wine: skipped for $STAGENAME (no execution patterns found)"
        eval "$errexit_state"; return 0
    fi

    log_info "${START_MARK} Wine required for $STAGENAME — initializing..."

    # Start virtual display if not already running
    if ! pgrep -x "Xvfb" > /dev/null 2>&1; then
        log_info "${START_MARK} Initializing Xvfb on :99 for Wine tests..."
        # Запуск на дисплее 99 без xvfb-run (меньше оверхед)
        ( Xvfb :99 -screen 0 1024x768x16 >/dev/null 2>&1 & )
        local retry=0
        while [[ $retry -lt 15 ]]; do
            DISPLAY=:99 xset -q >/dev/null 2>&1 && break
            sleep 0.2
            (( retry++ ))
        done
        if [[ $retry -ge 15 ]]; then
            log_warn "Xvfb did not start in time - Wine tests may fail"
        fi
    fi

    export DISPLAY=:99

    # Warm up Wine server asynchronously

    ( wineboot -u >/dev/null 2>&1 & )

    eval "$errexit_state"
}
export -f setup_wine_env

# Очистка при выходе. Удаляем старые файлы, если они остались от прошлых запусков
stage_cleanup() {
    local exit_code=$?
    local duration=$SECONDS
    local elapsed=$(printf '%02dh:%02dm:%02ds' $((duration/3600)) $((duration%3600/60)) $((duration%60)))
    local BUILD_DIR="/build/${STAGENAME}"

    if [[ $exit_code -eq 0 ]]; then
        # Успех: чистим всё; NOTE: Should keep "$VARS_DIR" & "$OUTFILE"
        cd /
        [[ -n "$STAGENAME" ]] && rm -rf "$BUILD_DIR"
        rm -f "$STAGE_LOG" "$TIMESTAMP_FILE"
        log_info "${CHECK_MARK} Build ${GREEN}SUCCEEDED${NC} for ${STAGENAME} [Time: ${GREY_B}${elapsed}${NC}]"
    else
        # Неудача: дампим логи
        log_error "Build ${LOG_ERROR}FAILED${NC} for ${STAGENAME} after ${GREY_B}${elapsed}${NC}"
        if [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]]; then
            log_debug "${BUILD_MARK} Current stage file: ${STAGE}"
            log_debug "${DIRS_MARK} Current directory: $(pwd)"
            cd /build
            LOG_FILES=$(find "$BUILD_DIR" -maxdepth 4 \( -name "config.log" -o -name "meson-log.txt" -o -name "CMakeError.log" -o -name "CMakeOutput.log" \) 2>/dev/null)
            if [[ -n "$LOG_FILES" ]]; then
                # Удача: выводим найденные логи систем сборки
                for logfile in $LOG_FILES; do
                    # Skip if this is the same as STAGE_LOG (already captured)
                    if [[ "$(readlink -f "$logfile")" == "$(readlink -f "$STAGE_LOG")" ]]; then
                        continue
                    fi
                    log_debug "${LOGS_MARK} ▼ CONTENT OF ${logfile} (last 300 lines) ▼"
                    tail -n 300 "$logfile" >&2
                    log_debug "${LOGS_MARK} ▲ END OF $(basename "$logfile") ▲"
                done
            else
                # Неудача: системных логов нет, ищем общий лог
                if [[ -f "$STAGE_LOG" ]]; then
                    log_debug "${LOGS_MARK} ▼ System logs missing. Falling back to STAGE_LOG ($STAGE_LOG) ▼"
                    tail -n 100 "$STAGE_LOG" >&2
                else
                    # Ничего не нашли
                    if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then
                        log_warn "No logs found. ${DIRS_MARK} Listing directory content of $BUILD_DIR:"
                        # 1) use find
                        # -maxdepth 2 чтобы не выводить тысячи файлов из подпапок
                        # sed добавляет отступы для имитации дерева
                        find "$BUILD_DIR" -maxdepth 2 -not -path '*/.*' | sed -e "s|^$BUILD_DIR||" -e "s|^/||" | sort | while read -r line; do
                            [[ -z "$line" ]] && continue
                            full_path="${BUILD_DIR}/${line}"
                            if [[ -d "$full_path" ]]; then
                                echo -e "  ${DIRS_MARK} ${BLUE_B}${line}/${NC}" >&2
                            elif [[ -x "$full_path" ]]; then
                                echo -e "  ${CHECK_MARK} ${GREEN}${line}*${NC}" >&2
                            else
                                echo -e "    ${line}" >&2
                            fi
                        done
                        # 2) or use ls
                        # ls -F -C --color=always --group-directories-first "$BUILD_DIR" >&2
                        # 3) better use tree (need rebuild)
                        # -F добавляет / к папкам, -L 2 ограничивает глубину, чтобы не спамить
                        # --dirsfirst группирует папки в начале
                        # tree -F -L 2 --dirsfirst "$BUILD_DIR" >&2
                    else
                        log_warn "No logs were found."
                    fi
                fi
            fi
        else
            if [[ -f "$STAGE_LOG" ]]; then
                log_debug "${LOGS_MARK} ▼ CONTENT OF ($STAGE_LOG) ▼"
                tail -n 100 "$STAGE_LOG" >&2
                log_debug "${LOGS_MARK} ▲ END OF $STAGE_LOG ▲"
            else
                log_warn "Log file $STAGE_LOG is missing!"
            fi
        fi
        cd /
        # Чистка после падения
        rm -rf "$BUILD_DIR" "$VARS_DIR" "$STAGE_LOG" "$TIMESTAMP_FILE" "$OUTFILE"
    fi
}
trap stage_cleanup EXIT

# Создаем и входим в директорию сборки ДО загрузки скрипта
mkdir -p "/build/$STAGENAME" && cd "/build/$STAGENAME"

# Подгружаем скрипт заранее, чтобы проверить SCRIPT_SKIP
# любые $(pwd) или относительные пути внутри скрипта будут указывать на /build/STAGENAME
# Используем абсолютный путь к скрипту, так как мы уже сменили cd
source "$(readlink -f "$STAGE")"

# Проверка на пропуск (теперь переменная SCRIPT_SKIP подгружена в контексте нужной папки)
if [[ "$SCRIPT_SKIP" == "1" ]]; then
    log_info "Skipping stage $STAGENAME as requested by script."
    exit 0
fi

# Очищаем временный приемник файлов, чтобы избежать "паразитного" копирования 
# артефактов из предыдущих слоев Docker (если они попали в кэш слоя)
if [[ -d "$FFBUILD_DESTDIR" ]]; then
    log_info "${BROOM_MARK} Cleaning up temporary DESTDIR: $FFBUILD_DESTDIR"
    rm -rf "${FFBUILD_DESTDIR:?}"/*
fi
mkdir -p "$FFBUILD_DESTDIR" "$FFBUILD_DESTPREFIX"

log_info "${SEARCH_MARK} Searching source for $STAGENAME"

# Ищем точное совпадение (Имя_Хеш)
if [[ -f "$STAGE_CACHE_FILE" ]]; then
    REAL_CACHE="$STAGE_CACHE_FILE"
    log_info "${CHECK_MARK} Exact cache match found: $(basename "$REAL_CACHE")"
    ln -sf "$(basename "$STAGE_CACHE_FILE")" "$STAGE_LATEST_LINK"
# Ищем по хешу (если скрипт переименован, например 25-glib2 -> 24-glib2)
else
    EXISTING_BY_HASH=$(find "$CACHE_DIR" -maxdepth 1 -name "*_${STAGE_HASH}.tar.zst" -print -quit)
    if [[ -n "$EXISTING_BY_HASH" ]]; then
        REAL_CACHE="$EXISTING_BY_HASH"
        log_info "${CHECK_MARK} Found cache with matching hash but different name: $(basename "$REAL_CACHE")"
        ln -sf "$(basename "$REAL_CACHE")" "$STAGE_LATEST_LINK"
# Откат к последней ссылке (LATEST), если точный хеш не найден
    elif [[ -L "$STAGE_LATEST_LINK" && -f "$STAGE_LATEST_LINK" ]]; then
        REAL_CACHE=$(readlink -f "$STAGE_LATEST_LINK")
        log_warn "Exact hash $STAGE_HASH not found. Falling back to latest symlink: $(basename "$REAL_CACHE")"
    fi
fi

# Проверяем, нужны ли вообще исходники для этой стадии (или это мета-стадия), и выходим
DL_COMMANDS=$(ffbuild_dockerdl 2>/dev/null) || {
    log_error "ffbuild_dockerdl failed for $STAGENAME"
    exit 1
}

if [[ -n "$DL_COMMANDS" ]]; then
    # Если кэш не найден ни одним способом
    if [[ -z "$REAL_CACHE" || ! -f "$REAL_CACHE" ]]; then
        log_warn "Source cache NOT FOUND for $STAGENAME. Attempting direct download..."
        log_debug "Expected hash: $STAGE_HASH | Target file: $STAGE_CACHE_FILE"

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
            tar -I 'zstd -T0 -3' -cf "$STAGE_CACHE_FILE" .
            ln -sf "$(basename "$STAGE_CACHE_FILE")" "$STAGE_LATEST_LINK"
        else
            # блок ошибки, срабатывает только если загрузка провалилась.
            log_error "ERROR: No source cache and download failed for $STAGENAME"
            log_info "Expected hash: $STAGE_HASH"
            if [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]]; then
                log_debug "${DIRS_MARK} Available files in cache for this component:"
                ls -lh "$CACHE_DIR" | grep "$STAGENAME" || log_warn "No files matching $STAGENAME found."
            fi
            exit 1
        fi
    else
        # Если REAL_CACHE был найден (одним из 3-х способов выше)
        log_info "${EXTR_MARK} Unpacking $STAGENAME from $(basename "$REAL_CACHE")..."
        if ! tar -I 'zstd -d -T0' -xaf "$REAL_CACHE" -C . ; then log_error "Failed to unpack $(basename "$REAL_CACHE")"; exit 1; fi
    fi

    # АВТО-ПОИСК корня проекта (если архив распаковался в подпапку)
    if [[ "$USE_CONF_FINDER" != "1" ]] && [[ ! -f "Configure" && ! -f "configure" && ! -f "CMakeLists.txt" && ! -f "meson.build" ]]; then
        log_warn "No build file in root. ${SEARCH_MARK} Searching one level deeper..."
        CANDIDATE=$(find . -maxdepth 2 \( -name "Configure" -o -name "configure" -o -name "CMakeLists.txt" -o -name "meson.build" \) -printf '%h\n' | head -n 1)
        if [[ -n "$CANDIDATE" ]]; then
            log_info "${DIRS_MARK} Project root found at $CANDIDATE. Entering..."
            cd "$CANDIDATE"
        else # this is harming
            USE_CONF_FINDER=1
            conf_finder # try to regenerate conf
        fi
    fi

    # Проверка, что после всех манипуляций папка не пуста
    if [[ -z "$(ls -A)" ]]; then
        log_error "ERROR: Build directory is empty after unpacking/downloading $STAGENAME!"
        exit 1
    fi

    # АВТО-ПАТЧИНГ
    if [[ "$SKIP_PRE_PATCH" == "0" ]]; then
        log_info "${SEARCH_MARK} Checking for patches for ${STAGENAME}..."
        if [[ -d "$PATCHES_DIR/$COMPONENT_NAME" ]]; then
            apply_patches 
        else
            log_info "${CHECK_MARK} No patches found."
        fi
    else
        log_info "Skipping patches for $STAGENAME"
    fi

    if [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]]; then
        log_debug "${DIRS_MARK} Contents of $(pwd) (current build directory):"
        # Собираем список: сначала папки (с /), потом файлы
        # -F добавляет / к папкам, -1 выводит в один столбец
        # paste объединяет их через табуляцию, чтобы column понял разделитель
        paste <(ls -d */ 2>/dev/null | head -n 15) \
              <(ls -F 2>/dev/null | grep -v / | head -n 15) | \
              column -t -s $'\t' -N "DIRECTORIES","FILES" | \
              sed 's/^/ /' # Добавляем отступ слева для красоты
    fi

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

[[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]] && log_debug "${STAGENAME}-specific CFLAGS:\n$CFLAGS"

# Выполняем сборку ОДИН РАЗ с проверкой статуса
build_cmd="ffbuild_dockerbuild"
[[ -n "$2" ]] && build_cmd="$2"

# wine starter
setup_wine_env

log_info_line
log_info "### ${START_MARK} ${LOG_INFO}STARTING STAGE: $STAGENAME${NC}"
log_info "### DATE: $(date)"
log_info "### Starting build function: $build_cmd"
log_info_line

# Generate the 'configure' file (if it doesn't exist) for Autoconf
# conf_finder

if [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]]; then
    log_debug "Verbose mode active. Build output will be shown in real-time."
    if ! ( set -e -o pipefail; $build_cmd ); then exit 1; fi
else
    log_info "Quiet mode active. Output is redirected to ${STAGE_LOG}"
    if ! ( set -e -o pipefail; $build_cmd > "${STAGE_LOG}" 2>&1 ); then exit 1; fi
fi

log_info_line
log_info "### ${SYNC_MARK} POST-BUILD AUDIT AND AUTOMATION: $STAGENAME"
log_info_line

# Каждый скрипт в scripts.d обязан устанавливать файлы (make install) в путь, начинающийся с $FFBUILD_DESTDIR$FFBUILD_PREFIX (обычно это /opt/ffdest/opt/ffbuild), иначе система не увидит установленную библиотеку для следующего этапа.
# The key constraint is: strip before sync, clean before strip, patch .pc before sync.
# build_cmd runs
# ▼
# [AUDIT]   Verify INSTALL_ROOT exists and has files
# │         (fail fast — no point running anything else on empty install)
# ▼
# [CLEAN]   clean_la_files          ← remove .la before anything reads them
# │         (.la files can poison pkgconfig and linker lookups)
# ▼
# [CLEAN]   Remove unwanted DLLs / static .a  ← based on PREFER_SHARED + preserve lists
# │         (must happen BEFORE strip — no point stripping files we're about to delete)
# ▼
# [STRIP]   strip_files             ← strip what remains after cleanup
# │         (strip DESTPREFIX, not PREFIX — we haven't synced yet)
# ▼
# [PATCH]   patch_pc_files          ← fix .pc paths AFTER strip (strip doesn't touch .pc)
# │         (paths must be correct before rsync writes them to PREFIX)
# ▼
# [SYNC]    rsync DESTPREFIX → PREFIX  ← only clean, stripped, patched files go to cache
# ▼
# [AUDIT]   get_deps_list           ← audit what landed in PREFIX (verbose only)
if [[ -d "$INSTALL_ROOT" ]]; then
    # Identify what was actually built
    mapfile -t NEW_FILES < <(find "$INSTALL_ROOT" -type f -o -type l)

    if [[ ${#NEW_FILES[@]} -eq 0 ]]; then
        log_warn "Stage $STAGENAME finished but no files were found in DESTDIR."
    else
        if [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]]; then
            # Show everything that was installed in a pretty way
            log_debug "${DIRS_MARK} Installed ${#NEW_FILES[@]} files to prefix:"
            # Очищаем пути от DESTDIR; можно попытаться и с "grep -Po"
            CLEAN_LIST=$(printf "%s\n" "${NEW_FILES[@]}" | sed "s|^$FFBUILD_DESTDIR||")
            (
                echo "$CLEAN_LIST" | grep -E "/lib/pkgconfig/|/lib/cmake/|/lib/[^/]+\.a$" | sort
                echo "$CLEAN_LIST" | grep -vE "/lib/pkgconfig/|/lib/cmake/|/lib/[^/]+\.a$" | sort
            ) | head -n 50 >&2
            # stripping the long DESTDIR prefix for readability
            [[ ${#NEW_FILES[@]} -gt 50 ]] && log_debug "  ... (and $((${#NEW_FILES[@]} - 50)) more)"
        fi

        # clean .la files (libtool archives)
        [[ "$SKIP_POST_CLEAN" != "1" ]] && clean_la_files

        # remove unwanted DLLs or static libs
        # список стадий, которым РАЗРЕШЕНО иметь DLL импортируется из workflow.yaml
        # библиотеки MinGW создают libимя.dll.a (implib) даже для статики
        if [[ "$PREFER_SHARED" != "1" ]]; then
            if [[ ! "$STAGENAME" =~ $DLL_PRESERVE_LIST ]]; then
                clean_unwanted_libs "dynamic DLLs" "\( -name '*.dll' -o -name '*.dll.a' \)"
            else
                log_info "${LOCK_MARK} Preserving dynamic DLLs and generating import libs for $STAGENAME"
                # First, create an .a file so ffmpeg can link to it.
                generate_implibs "$INSTALL_ROOT"
                # For TensorFlow/Torch, you often need to move DLLs to bin if they fall into lib; (must be covered by their scripts)
                # find "$INSTALL_ROOT/lib" -name "*.dll" -exec mv {} "$INSTALL_ROOT/bin/" \; 2>/dev/null || true
            fi
        else
            if [[ -n "$LIB_PRESERVE_LIST" && ! "$STAGENAME" =~ $LIB_PRESERVE_LIST ]]; then
                clean_unwanted_libs "static libs" "-name '*.a' ! -name '*.dll.a'"
            else
                log_info "${LOCK_MARK} Preserving static libs for $STAGENAME"
            fi
        fi

        # strip debug symbols
        [[ "$SKIP_POST_STRIP" != "1" ]] && strip_files "$INSTALL_ROOT" "$STAGENAME"

        # patch .pc files (пути, зависимости, Requires.private)
        # Флаг SKIP_POST_PATCH=1 в скрипте может это отключить при необходимости
        [[ "$SKIP_POST_PATCH" != "1" ]] && patch_pc_files

        # sync to persistent prefix (So the next script sees them)
        # Using -u (update) to avoid overwriting newer files if layers run out of order
        rsync -a --checksum "$INSTALL_ROOT/" "$FFBUILD_PREFIX/"
        log_info "${CHECK_MARK} Sync completed and $STAGENAME is now available for dependencies."

        # audit зависимостей (verbose only)
        [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]] && get_deps_list
    fi
else
    log_debug "${DIRS_MARK} No standard prefix directory found for $STAGENAME"
fi

# Сохраняем переменные для текущего слоя в файл 
OUTFILE="$VARS_DIR/${STAGENAME}.vars"

# Completely isolated subshell, no inherited FF_* state
# The subshell is the critical isolation mechanism, no FF_* state can leak in from the parent environment.
log_info "${SAVE_MARK} Saving build variables for $STAGENAME..."
(
    export PKG_CONFIG_LIBDIR="$PKG_CONFIG_LIBDIR"
    export PKG_CONFIG_PATH="$PKG_CONFIG_LIBDIR"
    # Re-source vars.sh clean so ffbuild_* accumulator functions are defined
    # but FF_* variables are empty
    unset FF_CONFIGURE FF_CFLAGS FF_CXXFLAGS FF_CPPFLAGS FF_LDFLAGS FF_LDEXEFLAGS FF_LIBS
    . "$UTIL_DIR/vars.sh" "$TARGET" "$VARIANT" > /dev/null 2>&1

    # Re-source the component script so its ffbuild_* functions are available
    # Load component - overrides ffbuild_* with its own implementations
    . "$STAGE"

    # Call the component's own ffbuild_* functions
    # These are the ONLY authoritative source of what this component needs.
    _conf=$(ffbuild_configure 2>/dev/null || true)
    _cf=$(ffbuild_cflags 2>/dev/null || true)
    _cpp=$(ffbuild_cppflags 2>/dev/null || true)
    _cxx=$(ffbuild_cxxflags 2>/dev/null || true)
    _ld=$(ffbuild_ldflags 2>/dev/null || true)
    _ldexe=$(ffbuild_ldexeflags 2>/dev/null || true)
    _libs=$(ffbuild_libs 2>/dev/null || true)

    # Collect flags from this component's own .pc files only
    # (files newer than the pre-build timestamp)
    _pc_cflags=""
    _pc_libs=""
    declare -A _seen_pc_cflags
    declare -A _seen_pc_libs

    # This is much more reliable than name matching, it doesn't matter what the library calls its .pc file. Only .pc files newer than the pre-build timestamp

    for pc in "$FFBUILD_PREFIX/lib/pkgconfig"/*.pc \
              "$FFBUILD_PREFIX/lib64/pkgconfig"/*.pc \
              "$FFBUILD_PREFIX/share/pkgconfig"/*.pc; do
        [[ -e "$pc" ]] || continue
        [[ "$pc" -nt "$TIMESTAMP_FILE" ]] || continue

        # Собираем только если имя .pc файла соответствует или связано с компонентом
        pc_name="$(basename "$pc" .pc)"

        # Deduplicate per-flag across multiple .pc files
        while IFS= read -r flag; do
            [[ -z "$flag" ]] && continue
            if [[ -z "${_seen_pc_cflags[$flag]:-}" ]]; then
                _seen_pc_cflags["$flag"]=1
                _pc_cflags="$_pc_cflags $flag"
            fi
        # просто pkg-config --cflags сохраняет с путями
        done < <(pkg-config $PKG_CONFIG_CFLAGS "$pc_name" 2>/dev/null \
                 | tr ' ' '\n' | grep -v '^$')

        # Сначала собираем сами библиотеки (-l)
        # while IFS= read -r flag; do
            # [[ -z "$flag" ]] && continue
            # if [[ -z "${_seen_pc_libs[$flag]:-}" ]]; then
                # _seen_pc_libs["$flag"]=1
                # _pc_libs="$_pc_libs $flag"
            # fi
        # done < <(pkg-config $PKG_CONFIG_LIBS "$pc_name" 2>/dev/null | tr ' ' '\n' | grep -v '^$')

        # Затем собираем системные флаги (-pthread и т.д.)
        while IFS= read -r flag; do
            [[ -z "$flag" ]] && continue
            if [[ -z "${_seen_pc_libs[$flag]:-}" ]]; then
                _seen_pc_libs["$flag"]=1
                _pc_libs="$_pc_libs $flag"
            fi
        done < <(pkg-config $PKG_CONFIG_ALL_LIBS "$pc_name" 2>/dev/null | tr ' ' '\n' | grep -v '^$')
    done

    # Merge script output with .pc output, then deduplicate the combined result
    FF_CONFIGURE=$(smart_dedupe "$_conf")
    FF_CFLAGS=$(smart_dedupe "$_cf $_pc_cflags")
    FF_CPPFLAGS=$(smart_dedupe "$_cpp")
    FF_CXXFLAGS=$(smart_dedupe "$_cxx")
    FF_LDFLAGS=$(smart_dedupe "$_ld")
    FF_LDEXEFLAGS=$(smart_dedupe "$_ldexe")
    FF_LIBS=$(smart_libs_dedupe "$_libs $_pc_libs")

    VARS_CONTENT=""
    [[ -n "$FF_CONFIGURE" ]]  && VARS_CONTENT+="export FF_CONFIGURE='${FF_CONFIGURE}'\n"
    [[ -n "$FF_CFLAGS" ]]     && VARS_CONTENT+="export FF_CFLAGS='${FF_CFLAGS}'\n"
    [[ -n "$FF_CPPFLAGS" ]]   && VARS_CONTENT+="export FF_CPPFLAGS='${FF_CPPFLAGS}'\n"
    [[ -n "$FF_CXXFLAGS" ]]   && VARS_CONTENT+="export FF_CXXFLAGS='${FF_CXXFLAGS}'\n"
    [[ -n "$FF_LDFLAGS" ]]    && VARS_CONTENT+="export FF_LDFLAGS='${FF_LDFLAGS}'\n"
    [[ -n "$FF_LDEXEFLAGS" ]] && VARS_CONTENT+="export FF_LDEXEFLAGS='${FF_LDEXEFLAGS}'\n"
    [[ -n "$FF_LIBS" ]]       && VARS_CONTENT+="export FF_LIBS='${FF_LIBS}'\n"

    # Write only non-empty values to .vars
    # Если есть хоть один экспорт пишем в файл
    if [[ -n "$VARS_CONTENT" ]]; then
        # printf '%b' is safe — no format string injection
        printf '%b' "$VARS_CONTENT" | tr -d '\r' > "$OUTFILE"
        log_debug "${CACHE_MARK} Saved $(wc -c < "$OUTFILE") bytes to $OUTFILE"
    else
        log_info "${CHECK_MARK} No build variables for $STAGENAME (meta/header-only)."
    fi

    # Verbose output - inside subshell where FF_* are populated
    if [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]]; then
        [[ -n "$FF_CONFIGURE" ]]  && log_debug "Final $STAGENAME FF_CONFIGURE:\n$FF_CONFIGURE"
        [[ -n "$FF_CFLAGS" ]]     && log_debug "Final $STAGENAME FF_CFLAGS:\n$FF_CFLAGS"
        [[ -n "$FF_CPPFLAGS" ]]   && log_debug "Final $STAGENAME FF_CPPFLAGS:\n$FF_CPPFLAGS"
        [[ -n "$FF_CXXFLAGS" ]]   && log_debug "Final $STAGENAME FF_CXXFLAGS:\n$FF_CXXFLAGS"
        [[ -n "$FF_LDFLAGS" ]]    && log_debug "Final $STAGENAME FF_LDFLAGS:\n$FF_LDFLAGS"
        [[ -n "$FF_LDEXEFLAGS" ]] && log_debug "Final $STAGENAME FF_LDEXEFLAGS:\n$FF_LDEXEFLAGS"
        [[ -n "$FF_LIBS" ]]       && log_debug "Final $STAGENAME FF_LIBS:\n$FF_LIBS"
    fi
)

if [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]]; then
    # Диагностика созданных файлов
    log_debug "${DIRS_MARK} Current files in $VARS_DIR:"
    ls -1 "$VARS_DIR" | grep ".vars" || log_warn "No .vars files created in this stage."
fi

# Вывод статистики в конце каждой стадии
# Это покажет Hit Rate прямо в логах GitHub
log_info "${CACHE_MARK} CCACHE STATISTICS:"
ccache -s

log_info_line
log_info "### ${CHECK_MARK} Post-build automation completed."
log_info_line

exit 0