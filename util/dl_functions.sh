#!/bin/bash

default_dl() {
    local TARGET_DIR="${1:-.}"
    if command -v git-mini-clone >/dev/null 2>&1; then
        # Если используем внутреннюю утилиту (в докере)
        echo "git-mini-clone \"$SCRIPT_REPO\" \"${SCRIPT_COMMIT:-master}\" \"$TARGET_DIR\""
    else
        # Эмуляция на хосте (GitHub Runner)
        local CMD="git clone --filter=blob:none --quiet \"$SCRIPT_REPO\" \"$TARGET_DIR\""
        if [[ -n "$SCRIPT_COMMIT" ]]; then
            CMD="$CMD && cd \"$TARGET_DIR\" && git checkout --quiet \"$SCRIPT_COMMIT\""
        fi
        echo "$CMD"
    fi
}

ffbuild_dockerdl() {
    default_dl "."
}
