#!/bin/bash

set -e

retry-tool() {
    _retry "$@"
}
export -f retry-tool

# Вспомогательная функция для надежного выполнения сетевых команд
_retry() {
    local n=1
    local max=3
    local delay=5
    local timeout_val=300
    
    while true; do
        if timeout --kill-after=10 "$timeout_val" "$@"; then
            return 0
        else
            if [[ $n -lt $max ]]; then
                log_warn "WARNING: Command failed: '$*'. Attempt $n/$max. Retrying in ${delay}s..."
                sleep "$delay"
                ((n++))
                delay=$((delay + 10))
            else
                log_error "ERROR: Command '$1' failed after $max attempts: $*"
                return 1
            fi
        fi
    done
}

git-mini-clone() {
    local REPO="$1"
    local COMMIT="$2"
    local TARGET_DIR="${3:-.}"
    local BRANCH_ARG="$4"

    if [[ -d "$TARGET_DIR/.git" ]]; then
        # Проверяем, не тот ли это уже коммит, который нам нужен
        local CURRENT_LOCAL_HEAD=$(cd "$TARGET_DIR" && git rev-parse HEAD 2>/dev/null || echo "none")
        if [[ "$CURRENT_LOCAL_HEAD" == "$COMMIT" ]]; then
            log_info "${TARGET_MARK} Git cache hit for $(basename "$REPO"): Commit $COMMIT already present."
            return 0
        fi
        log_warn "Cache miss for $(basename "$REPO"): Local=$CURRENT_LOCAL_HEAD Target=$COMMIT"
    fi

    local BRANCH="$BRANCH_ARG"
    if [[ -z "$BRANCH" ]]; then
        if [[ "$REPO" == "$SCRIPT_REPO" ]]; then BRANCH="$SCRIPT_BRANCH"
        elif [[ "$REPO" == "$SCRIPT_REPO2" ]]; then BRANCH="$SCRIPT_BRANCH2"
        elif [[ "$REPO" == "$SCRIPT_REPO3" ]]; then BRANCH="$SCRIPT_BRANCH3"
        elif [[ "$REPO" == "$SCRIPT_REPO4" ]]; then BRANCH="$SCRIPT_BRANCH4"
        fi
    fi

    # Определение TAGFILTER (для поддержки нескольких репо)
    local TAGFILTER=""
    if [[ "$REPO" == "$SCRIPT_REPO" ]]; then TAGFILTER="$SCRIPT_TAGFILTER"
    elif [[ "$REPO" == "$SCRIPT_REPO2" ]]; then TAGFILTER="$SCRIPT_TAGFILTER2"
    elif [[ "$REPO" == "$SCRIPT_REPO3" ]]; then TAGFILTER="$SCRIPT_TAGFILTER3"
    elif [[ "$REPO" == "$SCRIPT_REPO4" ]]; then TAGFILTER="$SCRIPT_TAGFILTER4"
    fi

    # Пропуск если SVN
    [[ -n "$SCRIPT_REV" ]] && { log_warn "SVN detected, skipping git"; return 0; }

    log_info "Trying to fetch from: $REPO @ $COMMIT"
    mkdir -p "$TARGET_DIR"

    # Запоминаем, где мы были
    local OLD_PWD=$(pwd)
    cd "$TARGET_DIR" || return 1
    # Функция для безопасного выхода (замена popd)
    trap "cd '$OLD_PWD'" RETURN

    # Удаляем возможные локи от прошлых неудачных запусков
    [[ -d ".git" ]] && rm -f .git/index.lock
    # Инициализируем один раз
    [[ ! -d ".git" ]] && git init -q

    # Настройка всех зеркал сразу
    git remote remove origin 2>/dev/null || true
    git remote add origin "$REPO"

    # Добавляем все зеркала в один список для перебора (SCRIPT_MIRROR)
    local i=1
    while :; do
        local m_var="SCRIPT_MIRROR$i"
        [[ $i -eq 1 && -z "${!m_var}" ]] && m_var="SCRIPT_MIRROR"
        [[ -z "${!m_var}" ]] && break
        git remote set-url --add origin "${!m_var}"
        ((i++))
    done

    # Обработка TAGFILTER перед скачиванием
    if [[ -n "$TAGFILTER" ]]; then
        log_debug "Resolving tag with filter: $TAGFILTER"
        local RESOLVED_COMMIT
        RESOLVED_COMMIT=$(git ls-remote --tags --sort="v:refname" origin "$TAGFILTER" | tail -n1 | awk '{print $1}')
        if [[ -n "$RESOLVED_COMMIT" ]]; then
            COMMIT="$RESOLVED_COMMIT"
        else
            log_error "Tag filter '$TAGFILTER' returned nothing"
            return 1
        fi
    fi

    local success=0

    # Прямой fetch коммита
    log_info "Fetching $(basename "$REPO") @ $COMMIT..."
    if _retry git -c advice.detachedHead=false fetch --quiet --no-tags --no-show-forced-updates --depth=1 origin "$COMMIT" >/dev/null 2>&1; then
        git checkout --quiet FETCH_HEAD && success=1
    fi

    # Если не вышло, пробуем через ветку
    if [[ $success -eq 0 && -n "$BRANCH" ]]; then
        log_warn "Direct fetch failed, trying branch: $BRANCH"
        if _retry git fetch --quiet --no-tags --depth=1 origin "$BRANCH"; then
             git checkout --quiet "$COMMIT" && success=1
        fi
    fi

    # Полный fallback (если сервер не поддерживает shallow fetch для коммитов)
    if [[ $success -eq 0 ]]; then
        log_warn "Shallow fetch failed. Performing full fallback for $REPO..."
        log_warn "Full fetch for $REPO may download significant data..."
        if _retry git fetch --quiet --tags origin || _retry git fetch --quiet origin; then
            git checkout --quiet "$COMMIT" && success=1
        fi
    fi

    if [[ $success -eq 0 ]]; then
        log_error "ERROR: Failed to clone $REPO at $COMMIT"
        return 1
    fi
    return 0
}

download_file() {
    local URL="$1"
    local DEST="$2"
    local SHA512="$3"

    # УДАЛЯЕМ старый/битый файл перед новой попыткой
    rm -f "$DEST"
    trap 'rm -f "$DEST"' EXIT

    # Проверка существующего и целого файла в кэше
    if [[ -f "$DEST" ]]; then
        if [[ -n "$SHA512" ]]; then
            if echo "$SHA512  $DEST" | sha512sum -c --status 2>/dev/null; then
                log_info "${TARGET_MARK} File $(basename "$DEST") matches cache."
                return 0
            fi
            log_warn "Checksum mismatch for $(basename "$DEST"), re-downloading..."
        else
            log_info "${CHECK_MARK} File $(basename "$DEST") exists, skipping."
            return 0
        fi
    fi

    log_info "${DOWN_MARK} Downloading file: $(basename "$DEST")"

    # Получаем размер файла через curl -I (если сервер поддерживает)
    local size=$(curl -sIL "$URL" | grep -i 'Content-Length' | awk '{print $2}' | tr -d '\r' | tail -n1)
    local useragent="Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36"
    #  Качаем через пайп с pv
    # Используем _retry только для curl, передавая его в пайп
    # PIPESTATUS[0] — это код curl, PIPESTATUS[1] — код pv
    # pv -n — выводит только число процентов (0..100)
    # pv -p — выводит прогресс-бар (лучше для локального терминала)
    # -f (fail silently) возвращает код 22 при 404 и триггерит _retry
    # -I информация
    # -L (location) следовать редиректам SourceForge
    local dl_cmd
    if [[ -n "$size" && "$size" -gt 0 ]]; then
        dl_cmd="curl -A \"$useragent\" -fsSL \"$URL\" | pv -n -s $size"
    else
        dl_cmd="curl -A \"$useragent\" -fsSL \"$URL\" | pv -b"
    fi

    # Выполняем через eval, чтобы правильно обработать пайп и логирование
    if eval "$dl_cmd > \"$DEST\" 2> >(while read line; do log_debug \"[DL] $line%\"; done)"; then
        # Проверяем код возврата именно первого элемента пайпа (curl)
        if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
            log_error "Curl failed with exit code ${PIPESTATUS[0]}"
            return 1
        fi
    else
        return 1
    fi

    # Финальная проверка хеша
    if [[ -n "$SHA512" ]]; then
        if ! echo "$SHA512  $DEST" | sha512sum -c --status; then
            log_error "Hash validation FAILED for $(basename "$DEST")"
            return 1
        fi
        log_info "${CHECK_MARK} Hash verified."
    fi

    return 0
}

git-submodule-clone() {
    log_info "${START_MARK} Starting robust submodule synchronization..."

    # Принудительно обновляем URL подмодулей из файла .gitmodules
    # Это решает проблему, если в репозитории изменились адреса подмодулей
    log_info "${SYNC_MARK} Syncing submodules..."
    git submodule sync --recursive

    # Попытка стандартного обновления
    # --force поможет, если локально были внесены небольшие изменения
    log_info "Attempting standard update..."
    if _retry git submodule update --quiet --init --recursive --depth 1; then
        log_info "${CHECK_MARK} Submodules synchronized successfully via standard update."
        return 0
    fi

    # Если не помогло, пробуем более агрессивный метод
    log_warn "Standard submodule update failed, trying manual foreach..."

    # используем || return 1, чтобы если foreach упадет, функция сразу вернула ошибку
    # 1. Сброс локальных изменений, которые могут мешать checkout
    # 2. Получаем данные напрямую
    # 3. Пытаемся переключиться на нужный коммит (записанный в основном репозитории)
    # Обычно это FETCH_HEAD после fetch, если мы тянем конкретный коммит
    git submodule foreach --recursive bash -c '
        source $UTIL_DIR/vars.sh "$TARGET" "$VARIANT" 2>/dev/null
        source $UTIL_DIR/dl_functions.sh
        log_info "Processing submodule: $name"
        git reset --hard HEAD && git clean -fd
        if _retry git fetch --quiet --no-tags --depth=1 origin; then
            git checkout -q FETCH_HEAD || git checkout -q $(git config -f $top_level/.gitmodules submodule.$name.branch || echo "master")
        else
            log_error "ERROR: Failed to fetch submodule $name"
            return 1
        fi
    '

    # Финальная проверка
    if [ $? -eq 0 ]; then
        log_info "${CHECK_MARK} Submodules synchronized after manual intervention."
        return 0
    else
        log_error "ERROR: Could not synchronize submodules."
        return 1
    fi
}

svn-mini-clone() {
    local REPO="$1"
    local REV="${2:-HEAD}"
    local TARGET_DIR="${3:-.}"

    [[ -z "$REV" ]] && REV="HEAD"

    log_info "Fetching SVN: $REPO@$REV"
    mkdir -p "$TARGET_DIR"

    # Добавляем --username 'anonymous' и --password ''
    # Добавляем --trust-server-cert для обхода проблем с SSL
    if _retry svn export --non-interactive \
        --username 'anonymous' --password '' \
        --trust-server-cert \
        --trust-server-cert-failures=unknown-ca,cn-mismatch,expired,not-yet-valid,other \
        "$REPO@$REV" "$TARGET_DIR" --force --quiet; then
        log_info "${CHECK_MARK} SVN export successful."
        return 0
    else
        log_error "ERROR: Failed to export SVN: $REPO (Check credentials or URL)"
        return 1
    fi
}

default_dl() {
    local TARGET_DIR="${1:-.}"

    # Если задан SVN
    if [[ -n "$SCRIPT_REV" ]]; then
        echo "svn-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_REV\" \"$TARGET_DIR\""
        return 0
    fi

    # Иначе работаем с Git
    local CMDS=()
    
    # Основной репозиторий
    if [[ -n "$SCRIPT_REPO" ]]; then
        local BASE_COMMIT="${SCRIPT_COMMIT:-master}"
        CMDS+=( "git-mini-clone \"$SCRIPT_REPO\" \"$BASE_COMMIT\" \"$TARGET_DIR\"" )
    fi

    # Зеркала 1..4
    for i in {1..4}; do
        local R_VAR="SCRIPT_REPO$i"
        local C_VAR="SCRIPT_COMMIT$i"
        if [[ -n "${!R_VAR}" ]]; then
            # Приоритет: Специфичный коммит зеркала -> Общий коммит -> master
            local TARGET_COMMIT="${!C_VAR:-${SCRIPT_COMMIT:-master}}"
            CMDS+=( "git-mini-clone \"${!R_VAR}\" \"$TARGET_COMMIT\" \"$TARGET_DIR\"" )
        fi
    done

    # Валидация
    if [[ ${#CMDS[@]} -eq 0 ]]; then
        # Пишем в stderr, чтобы не сломать eval/stdout
        log_error "No SCRIPT_REPO defined for stage!" >&2
        return 1
    fi

    # Формирование цепочки
    local FINAL_CHAIN=""
    for cmd in "${CMDS[@]}"; do
        if [[ -z "$FINAL_CHAIN" ]]; then
            FINAL_CHAIN="$cmd"
        else
            FINAL_CHAIN="$FINAL_CHAIN && $cmd"
        fi
    done

    echo "$FINAL_CHAIN"
}

download_stage() {
    local STAGE="$1"
    local CACHE_DIR="${2:-$CACHE_DIR}"

    local STAGE_HASH STAGENAME COMPONENT_NAME STAGE_CACHE_FILE STAGE_LATEST_LINK
    eval "$(stage_vars "$STAGE")"

    local DL_COMMANDS
    DL_COMMANDS="$(bash --norc --noprofile -c "
        source \"${UTIL_DIR}/vars.sh\" \"${TARGET}\" \"${VARIANT}\" >/dev/null
        source \"${UTIL_DIR}/dl_functions.sh\"
        source \"${STAGE}\"
        ffbuild_enabled || exit 0
        ffbuild_dockerdl
    " 2>/tmp/dl_cmd_err_${STAGENAME} || true)"

    # Если команд нет — это стадия без исходников (мета-пакет), выходим
    if [[ -z "$DL_COMMANDS" ]]; then
        # Log any real error from the subshell
        [[ -s "/tmp/dl_cmd_err_${STAGENAME}" ]] && \
            log_warn "dl subshell stderr for ${STAGENAME}:" && \
            cat "/tmp/dl_cmd_err_${STAGENAME}" >&2
        rm -f "/tmp/dl_cmd_err_${STAGENAME}"
        return 0  # meta-package, nothing to download
    fi
    rm -f "/tmp/dl_cmd_err_${STAGENAME}"

    # Проверяем, что у нас есть путь к кэшу, иначе упадем на mkdir/tar
    if [[ -z "$CACHE_DIR" ]]; then
        log_error "CACHE_DIR is empty! Check if vars.sh is sourced."
        return 1
    fi

    # Debug: show keep-list only at verbose >= 2
    if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then
        log_info "${DIRS_MARK} Files in cache for $STAGENAME:"
        ls -F "$CACHE_DIR" 2>/dev/null | grep "$STAGENAME" || log_warn "No files matching $STAGENAME found!"
    fi

    # Cache hit
    if [[ -f "$STAGE_CACHE_FILE" ]]; then
        local size
        size=$(du -sh "$STAGE_CACHE_FILE" | cut -f1)
        dl_result_line "hit" "$STAGENAME" "$STAGE_HASH" "$size"
        touch "$STAGE_CACHE_FILE"
        ln -sf "$(basename "$STAGE_CACHE_FILE")" "$STAGE_LATEST_LINK"
        return 0
    fi

    # Cache miss
    local miss_reason="no archive"
    [[ -L "$STAGE_LATEST_LINK" ]] && miss_reason="hash changed → ${STAGE_HASH:0:8}"
    dl_result_line "miss" "$STAGENAME" "$STAGE_HASH" "$miss_reason"
    log_warn "Cache miss: $STAGENAME ($miss_reason). ${DOWN_MARK} Re-downloading..."

    # Используем временную папку внутри проекта как рабочую
    local WORK_DIR=$(mktemp -d -p "$TMP_DIR")
    # Очистка при выходе. Удаляем только WORK_DIR конкретного процесса, а не весь TMP_DIR!
    # Иначе параллельные процессы удалят чужие папки.
    trap 'rm -rf "$WORK_DIR"' EXIT

    # Выполняем загрузку
    if (
        cd "$WORK_DIR"
        # Явно подгружаем функции внутри подоболочки для надежности в Parallel
        # source "$UTIL_DIR/vars.sh" "$TARGET" "$VARIANT" &>/dev/null
        # source "$UTIL_DIR/dl_functions.sh"
        eval "$DL_COMMANDS"
    ); then

        # Whitelist метаданных .git (список подгружается из workflow.yaml). 
        local PRESERVE_PATTERN="${GIT_PRESERVE_LIST// /:-ffmpeg|glib2}"

        if [[ "$STAGENAME" =~ $PRESERVE_PATTERN ]]; then
            log_info "${LOCK_MARK} Preserving Git metadata for $STAGENAME (Whitelist match)"
        else
            log_debug "${BROOM_MARK} Stripping Git metadata for $STAGENAME to save cache space"
            # Удаляем .git папки и .gitignore файлы
            find "$WORK_DIR" -maxdepth 2 -name ".git*" -exec rm -rf {} + 2>/dev/null || true
        fi

        mkdir -p "$(dirname "$STAGE_CACHE_FILE")"
        # Упаковка; -c: создать, -f: файл, -I 'zstd -T0 -3': -T0 задействует все ядра, -3 — оптимальный баланс скорости/сжатия
        tar -I 'zstd -T0 -3' -cf "$STAGE_CACHE_FILE" -C "$WORK_DIR" .
        ln -sf "$(basename "$STAGE_CACHE_FILE")" "$STAGE_LATEST_LINK"
        local final_size
        final_size=$(du -sh "$STAGE_CACHE_FILE" | cut -f1)
        # Update the result line from miss → cached (overwrite by appending corrected line)
        dl_result_line "miss" "$STAGENAME" "$STAGE_HASH" "downloaded → ${final_size}"
        log_info "${CACHE_MARK} Cached $STAGENAME (${final_size})"
        return 0
    else
        dl_result_line "fail" "$STAGENAME" "$STAGE_HASH" "download failed"
        log_error "FAILED to download $STAGENAME"
        [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]] && log_debug "$DL_COMMANDS"
        # rm -rf "$WORK_DIR" # Явное удаление
        return 1 # return 1 для параллельного запуска
    fi
}
export -f download_stage
