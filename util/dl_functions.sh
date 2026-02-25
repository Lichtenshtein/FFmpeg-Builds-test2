#!/bin/bash

retry-tool() {
    _retry "$@"
}
export -f retry-tool

# Вспомогательная функция для надежного выполнения сетевых команд
_retry() {
    local n=1
    local max=3  # Достаточно для нестабильных соединений
    local delay=5
    local timeout_val=300 # 20 минут на одну операцию
    
    while true; do
        if timeout "$timeout_val" "$@"; then
            return 0
        else
            if [[ $n -lt $max ]]; then
                log_warn "Warning: Command failed: '$*'. Attempt $n/$max. Retrying in ${delay}s..."
                sleep "$delay"
                ((n++))
                delay=$((delay + 10)) # Экспоненциальная задержка
            else
                log_error "Error: Command '$1' failed after $max attempts: $*"
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
            log_info "Git cache hit for $(basename "$REPO"): Commit $COMMIT already present."
            return 0
        fi
        log_debug "Cache miss for $(basename "$REPO"): Local=$CURRENT_LOCAL_HEAD Target=$COMMIT"
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
    _cleanup_git_clone() { cd "$OLD_PWD"; }

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
            _cleanup_git_clone; return 1
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
        if _retry git fetch --quiet --tags origin || _retry git fetch --quiet origin; then
            git checkout --quiet "$COMMIT" && success=1
        fi
    fi

    # Возвращаемся в исходную директорию
    _cleanup_git_clone
    if [[ $success -eq 0 ]]; then
        log_error "Error: Failed to clone $REPO at $COMMIT"
        return 1
    fi
    return 0
}

download_file() {
    local URL="$1"
    local DEST="$2"
    local SHA512="$3"

    # Проверка существующего файла (логика из check-wget.sh)
    if [[ -f "$DEST" ]]; then
        if [[ -n "$SHA512" ]]; then
            if echo "$SHA512  $DEST" | sha512sum -c --status 2>/dev/null; then
                log_info "File $(basename "$DEST") matches cache."
                return 0
            fi
            log_warn "Checksum mismatch for $(basename "$DEST"), re-downloading..."
        else
            log_info "File $(basename "$DEST") exists, skipping."
            return 0
        fi
    fi

    log_info "Downloading external file: $(basename "$DEST")..."
    # Заменяем wget на curl с поддержкой докачки и повторов
    if _retry curl -sL -C - "$URL" -o "$DEST"; then
        if [[ -n "$SHA512" ]]; then
            echo "$SHA512  $DEST" | sha512sum -c || { log_error "Hash validation failed"; return 1; }
        fi
        return 0
    fi
    return 1
}

git-submodule-clone() {
    log_info "Starting robust submodule synchronization..."

    # Принудительно обновляем URL подмодулей из файла .gitmodules
    # Это решает проблему, если в репозитории изменились адреса подмодулей
    log_info "Syncing submodules..."
    git submodule sync --recursive

    # Попытка стандартного обновления
    # --force поможет, если локально были внесены небольшие изменения
    log_info "Attempting standard update..."
    if _retry git submodule update --quiet --init --recursive --depth 1; then
        log_info "Submodules synchronized successfully via standard update."
        return 0
    fi

    # Если не помогло, пробуем более агрессивный метод
    log_warn "Standard submodule update failed, trying manual foreach..."

    # используем || return 1, чтобы если foreach упадет, функция сразу вернула ошибку
    git submodule foreach --recursive '
        echo "Processing submodule: $name"
        # Сброс локальных изменений, которые могут мешать checkout
        git reset --hard HEAD && git clean -fd

        # Получаем данные напрямую
        if _retry git fetch --quiet --no-tags --depth=1 origin; then
            # Пытаемся переключиться на нужный коммит (записанный в основном репозитории)
            # Обычно это FETCH_HEAD после fetch, если мы тянем конкретный коммит
            git checkout -q FETCH_HEAD || git checkout -q $(git config -f $top_level/.gitmodules submodule.$name.branch || echo "master")
        else
            echo "Failed to fetch submodule $name"
            exit 1
        fi
    '

    # Финальная проверка
    if [ $? -eq 0 ]; then
        log_info "Submodules synchronized after manual intervention."
        return 0
    else
        log_error "Critical failure: Could not synchronize submodules."
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

    # Добавляем --username 'anonymous' и --password '' как в оригинале
    # Добавляем --trust-server-cert для обхода проблем с SSL
    if _retry svn export --non-interactive \
        --username 'anonymous' --password '' \
        --trust-server-cert \
        --trust-server-cert-failures=unknown-ca,cn-mismatch,expired,not-yet-valid,other \
        "$REPO@$REV" "$TARGET_DIR" --force --quiet; then
        log_info "SVN export successful."
        return 0
    else
        log_error "Error: Failed to export SVN: $REPO (Check credentials or URL)"
        return 1
    fi
}

default_dl() {
    local TARGET_DIR="${1:-.}"

    # Если это SVN
    if [[ -n "$SCRIPT_REV" ]]; then
        echo "svn-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_REV\" \"$TARGET_DIR\""
        return
    fi

    # Формируем цепочку попыток для Git
    local CMDS=()

    # Основной Git репозиторий
    CMDS+=( "git-mini-clone \"$SCRIPT_REPO\" \"${SCRIPT_COMMIT:-master}\" \"$TARGET_DIR\"" )

    # Перебор индексов 1..4 (или больше, если нужно)
    for i in {1..4}; do
        local R_VAR="SCRIPT_REPO$i"
        local C_VAR="SCRIPT_COMMIT$i"
        # Если переменная репозитория существует (не пустая)
        if [[ -n "${!R_VAR}" ]]; then
            # Используем коммит этого индекса, или основной, если индексного нет
            local TARGET_COMMIT="${!C_VAR:-$SCRIPT_COMMIT}"
            CMDS+=( "git-mini-clone \"${!R_VAR}\" \"$TARGET_COMMIT\" \"$TARGET_DIR\"" )
        fi
    done

    # Скрипт будет пробовать их по очереди, пока одна не вернет 0 (успех)
    local FINAL_CHAIN=""
    for cmd in "${CMDS[@]}"; do
        if [[ -z "$FINAL_CHAIN" ]]; then
            FINAL_CHAIN="$cmd"
        else
            FINAL_CHAIN="$FINAL_CHAIN || $cmd"
        fi
    done

    echo "$FINAL_CHAIN"
}

ffbuild_dockerdl() {
    [[ -n "$SCRIPT_REPO" ]] && default_dl .
}
