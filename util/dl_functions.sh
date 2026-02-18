#!/bin/bash

git-mini-clone() {
    local REPO="$1"
    local COMMIT="$2"
    local TARGET_DIR="${3:-.}"

    # Определение веток для конкретных репозиториев
    local BRANCH="${SCRIPT_BRANCH:-}"
    [[ "$REPO" == "$SCRIPT_REPO1" && -n "$SCRIPT_BRANCH1" ]] && BRANCH="$SCRIPT_BRANCH1"
    [[ "$REPO" == "$SCRIPT_REPO2" && -n "$SCRIPT_BRANCH2" ]] && BRANCH="$SCRIPT_BRANCH2"
    [[ "$REPO" == "$SCRIPT_REPO3" && -n "$SCRIPT_BRANCH3" ]] && BRANCH="$SCRIPT_BRANCH3"
    [[ "$REPO" == "$SCRIPT_REPO4" && -n "$SCRIPT_BRANCH4" ]] && BRANCH="$SCRIPT_BRANCH4"

    [[ -n "$SCRIPT_REV" ]] && { log_warn "SVN detected, skipping git"; return 0; }

    mkdir -p "$TARGET_DIR"

    # Сохраняем текущий путь, чтобы вернуться в него в конце функции
    pushd "$TARGET_DIR" > /dev/null || return 1

    # Инициализируем один раз
    if [[ ! -d ".git" ]]; then
        git init -q
    fi

    # Настройка всех зеркал сразу
    git remote remove origin 2>/dev/null || true
    git remote add origin "$REPO"
    
    # Добавляем все зеркала в один список для перебора
    local i=1
    while :; do
        local mirror_var="SCRIPT_MIRROR$i"
        [[ $i -eq 1 ]] && mirror_var="SCRIPT_MIRROR" # Обработка первого зеркала без индекса
        local mirror_url="${!mirror_var}"
        [[ -z "$mirror_url" ]] && break
        git remote set-url --add origin "$mirror_url"
        ((i++))
    done

    # Более надежное получение SHA и тэгов
    if [[ -n "$SCRIPT_TAGFILTER" ]]; then
        log_debug "Resolving tag with filter: $SCRIPT_TAGFILTER"
        COMMIT=$(git ls-remote --tags --sort="v:refname" origin "$SCRIPT_TAGFILTER" | tail -n1 | awk '{print $1}')
        [[ -z "$COMMIT" ]] && { log_error "Tag filter returned nothing"; popd >/dev/null; return 1; }
    fi

    local success=0
    # Получаем все URL и пробуем fetch
    mapfile -t URLS < <(git remote get-url --all origin)

    # Цикл перебора зеркал БЕЗ пересоздания .git
    for url in "${URLS[@]}"; do
        log_debug "Trying fetch from $url (Commit: $COMMIT)..."
        # Прямая проверка команды без subshell
        if git fetch --quiet --depth=1 "$url" "$COMMIT" 2>/dev/null; then
            git checkout --quiet FETCH_HEAD
            success=1 && break
        fi
    done

    # Fallback на ветку, если прямой fetch коммита запрещен сервером
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
    [[ $success -eq 0 ]] && { log_error "Failed to clone $REPO at $COMMIT"; return 1; }
    return 0
}

download_file() {
    local URL="$1"
    local DEST="$2"
    
    # КЭШИРОВАНИЕ CURL, проверка локального файла
    if [[ -f "$DEST" ]]; then
        log_info "File $(basename "$DEST") already exists in cache, skipping download."
        return 0
    fi

    log_info "Downloading external file: $(basename "$DEST")..."
    # Добавлены флаги для стабильности: -C - (продолжение загрузки), --retry
    if ! curl -sL --retry 5 --retry-delay 2 -C - "$URL" -o "$DEST"; then
        log_error "Failed to download $URL"
        return 1
    fi
}

git-submodule-clone() {
    # Эта функция вызывается ПОСЛЕ того, как основной репозиторий уже склонирован в текущую директорию
    log_info "Synchronizing submodules (shallow)..."
    
    # Инициализируем подмодули
    git submodule init
    
    # Получаем список путей подмодулей и скачиваем их по одному с глубиной 1
    git submodule foreach --recursive '
        remote_url=$(git config --get remote.origin.url)
        git fetch --depth=1 origin
        git checkout -q FETCH_HEAD
    '
}

svn-mini-clone() {
    local REPO="$1"
    local REV="$2"
    local TARGET_DIR="${3:-.}"

    [[ -z "$REV" ]] && REV="HEAD"

    log_info "Fetching SVN (Anonymous): $REPO (Rev: $REV)..."
    mkdir -p "$TARGET_DIR"

    # Добавляем --username 'anonymous' и --password '' как в оригинале
    # Добавляем --trust-server-cert для обхода проблем с SSL
    if svn export --non-interactive \
        --username 'anonymous' --password '' \
        --trust-server-cert \
        --trust-server-cert-failures=unknown-ca,cn-mismatch,expired,not-yet-valid,other \
        "$REPO@$REV" "$TARGET_DIR" --force --quiet; then
        log_info "SVN export successful."
        return 0
    else
        log_error "Failed to export SVN: $REPO (Check credentials or URL)"
        return 1
    fi
}

default_dl() {
    local TARGET_DIR="${1:-.}"
    if [[ -n "$SCRIPT_REV" ]]; then
        # Если есть ревизия — это SVN, вызываем нашу новую функцию
        echo "svn-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_REV\" \"$TARGET_DIR\""
    elif [[ -n "$SCRIPT_REPO" ]]; then
        # Если ревизии нет, но есть репо — это Git
        echo "git-mini-clone \"$SCRIPT_REPO\" \"${SCRIPT_COMMIT:-master}\" \"$TARGET_DIR\""
    fi
}

ffbuild_dockerdl() {
    [[ -n "$SCRIPT_REPO" ]] && default_dl .
}
