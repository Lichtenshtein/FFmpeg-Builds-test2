#!/bin/bash

default_dl() {
    # Проверяем, существует ли git-mini-clone
    if command -v git-mini-clone >/dev/null 2>&1; then
        echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" \"$1\""
    else
        # Эмуляция git-mini-clone через стандартный git
        # $1 - это целевая папка (обычно ".")
        echo "git clone --filter=blob:none --quiet \"$SCRIPT_REPO\" \"$1\" && cd \"$1\" && git checkout --quiet \"$SCRIPT_COMMIT\""
    fi
}

ffbuild_dockerdl() {
    default_dl .
}
