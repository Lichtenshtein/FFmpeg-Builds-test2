#!/bin/bash

# Стандартная логика загрузки, если SCRIPT_REPO задан
default_dl() {
    local TARGET_DIR="${1:-.}"
    if [[ -z "$SCRIPT_REPO" ]]; then
        return 0
    fi
    
    if command -v git-mini-clone >/dev/null 2>&1; then
        echo "git-mini-clone \"$SCRIPT_REPO\" \"${SCRIPT_COMMIT:-master}\" \"$TARGET_DIR\""
    else
        local CMD="git clone --filter=blob:none --quiet \"$SCRIPT_REPO\" \"$TARGET_DIR\""
        if [[ -n "$SCRIPT_COMMIT" ]]; then
            CMD="$CMD && cd \"$TARGET_DIR\" && git checkout --quiet \"$SCRIPT_COMMIT\""
        fi
        echo "$CMD"
    fi
}

# Эта функция ДОЛЖНА БЫТЬ ОПРЕДЕЛЕНА, чтобы download.sh её видел
ffbuild_dockerdl() {
    default_dl .
}
