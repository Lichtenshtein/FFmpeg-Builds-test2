#!/bin/bash

git-mini-clone() {
    local REPO="$1"
    local COMMIT="$2"
    local TARGET_DIR="${3:-.}"
    
    # Пытаемся автоматически определить ветку, если переданы специфические переменные (как в ffnvcodec)
    # Если мы клонируем REPO4, проверим наличие SCRIPT_BRANCH4
    local BRANCH="${SCRIPT_BRANCH:-}"
    [[ "$REPO" == "$SCRIPT_REPO1" && -n "$SCRIPT_BRANCH1" ]] && BRANCH="$SCRIPT_BRANCH1"
    [[ "$REPO" == "$SCRIPT_REPO2" && -n "$SCRIPT_BRANCH2" ]] && BRANCH="$SCRIPT_BRANCH2"
    [[ "$REPO" == "$SCRIPT_REPO3" && -n "$SCRIPT_BRANCH3" ]] && BRANCH="$SCRIPT_BRANCH3"
    [[ "$REPO" == "$SCRIPT_REPO4" && -n "$SCRIPT_BRANCH4" ]] && BRANCH="$SCRIPT_BRANCH4"

    local TAGFILTER="${SCRIPT_TAGFILTER:-}"

    [[ -n "$SCRIPT_REV" ]] && { log_warn "SVN detected, skipping git"; return 0; }

    mkdir -p "$TARGET_DIR"

    # Сохраняем текущий путь, чтобы вернуться в него в конце функции
    pushd "$TARGET_DIR" > /dev/null || return 1

    # Инициализация
    git init -q
    # Очищаем старые origin, если папка переиспользуется
    git remote remove origin 2>/dev/null || true
    git remote add origin "$REPO"

    # Добавляем все возможные зеркала
    [[ -n "$SCRIPT_MIRROR" ]] && git remote set-url --add origin "$SCRIPT_MIRROR"
    [[ -n "$SCRIPT_MIRROR1" ]] && git remote set-url --add origin "$SCRIPT_MIRROR1"
    [[ -n "$SCRIPT_MIRROR2" ]] && git remote set-url --add origin "$SCRIPT_MIRROR2"
    [[ -n "$SCRIPT_MIRROR3" ]] && git remote set-url --add origin "$SCRIPT_MIRROR3"
    [[ -n "$SCRIPT_MIRROR4" ]] && git remote set-url --add origin "$SCRIPT_MIRROR4"

    if [[ -n "$TAGFILTER" ]]; then
        COMMIT=$(git ls-remote --tags --sort="v:refname" origin "$TAGFILTER" | tail -n1 | sed 's/.*\///')
    fi

    local success=0
    # Получаем все URL и пробуем fetch
    mapfile -t URLS < <(git remote get-url --all origin)
    
    for url in "${URLS[@]}"; do
        log_debug "Trying fetch from $url (Commit: $COMMIT)..."
        # Прямая проверка команды без subshell
        if git fetch --quiet --depth=1 "$url" "$COMMIT" 2>/dev/null; then
            git checkout --quiet FETCH_HEAD
            success=1 && break
        fi
    done

    # Fallback на ветку
    if [[ $success -eq 0 && -n "$BRANCH" ]]; then
        log_warn "Direct commit fetch failed, trying branch: $BRANCH"
        if git fetch --quiet --depth=1 origin "$BRANCH"; then
             git checkout --quiet "$COMMIT" && success=1
        fi
    fi

    # Последний шанс: Full Fetch
    if [[ $success -eq 0 ]]; then
        log_warn "Shallow fetch failed. Performing fallback full fetch..."
        if git fetch --quiet --tags origin || git fetch --quiet origin; then
            git checkout --quiet "$COMMIT" && success=1
        fi
    fi

    # Возвращаемся в исходную директорию
    popd > /dev/null

    # Если ничего не помогло — возвращаем ошибку основному скрипту
    if [[ $success -eq 0 ]]; then
        log_error "Failed to clone $REPO at $COMMIT"
        return 1
    fi
}

default_dl() {
    local TARGET_DIR="${1:-.}"
    [[ -z "$SCRIPT_REPO" ]] && return 0
    echo "git-mini-clone \"$SCRIPT_REPO\" \"${SCRIPT_COMMIT:-master}\" \"$TARGET_DIR\""
}

ffbuild_dockerdl() {
    [[ -n "$SCRIPT_REPO" ]] && default_dl .
}
