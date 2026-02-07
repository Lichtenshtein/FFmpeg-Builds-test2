#!/bin/bash

default_dl() {
    local TARGET_DIR="${1:-.}" # Если аргумент пуст, используем точку
    if command -v git-mini-clone >/dev/null 2>&1; then
        echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" \"$TARGET_DIR\""
    else
        # Используем git clone и checkout с явным указанием путей
        echo "git clone --filter=blob:none --quiet \"$SCRIPT_REPO\" \"$TARGET_DIR\" && cd \"$TARGET_DIR\" && git checkout --quiet \"$SCRIPT_COMMIT\""
    fi
}

ffbuild_dockerdl() {
    default_dl "."
}
