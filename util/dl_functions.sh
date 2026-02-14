#!/bin/bash

git-mini-clone() {
    local REPO="$1"
    local COMMIT="$2"
    local TARGET_DIR="${3:-.}"
    local BRANCH="${SCRIPT_BRANCH:-}"

    [[ "$TARGET_DIR" == "." ]] && TARGET_DIR="./"
    mkdir -p "$TARGET_DIR"

    # Если есть BRANCH, пробуем ее (depth 1)
    if [[ -n "$BRANCH" ]]; then
        if git clone --quiet --filter=blob:none --depth=1 --branch "$BRANCH" "$REPO" "$TARGET_DIR" 2>/dev/null; then
            if [[ -n "$COMMIT" && "$COMMIT" != "$BRANCH" ]]; then
                ( cd "$TARGET_DIR" && git fetch --quiet --depth=1 origin "$COMMIT" && git checkout --quiet FETCH_HEAD )
            fi
            return 0
        fi
    fi

    # Пробуем напрямую по COMMIT (теги/ветки)
    if git clone --quiet --filter=blob:none --depth=1 --branch "$COMMIT" "$REPO" "$TARGET_DIR" 2>/dev/null; then
        return 0
    fi

    # Фолбэк для специфических хэшей коммитов
    git clone --quiet --filter=blob:none --depth=1 "$REPO" "$TARGET_DIR" 2>/dev/null || git clone --quiet "$REPO" "$TARGET_DIR"
    cd "$TARGET_DIR"
    git fetch --quiet --depth=1 origin "$COMMIT" 2>/dev/null || git fetch --quiet origin "$COMMIT"
    git checkout --quiet FETCH_HEAD
}

default_dl() {
    local TARGET_DIR="${1:-.}"
    [[ -z "$SCRIPT_REPO" ]] && return 0
    echo "git-mini-clone \"$SCRIPT_REPO\" \"${SCRIPT_COMMIT:-master}\" \"$TARGET_DIR\""
}

ffbuild_dockerdl() {
    [[ -n "$SCRIPT_REPO" ]] && default_dl .
}
