#!/bin/bash
set -e
cd "$(dirname "$0")"
source util/vars.sh dl only
source util/dl_functions.sh

mkdir -p .cache/downloads
DL_DIR="$PWD/.cache/downloads"

# Эмуляция git-mini-clone для хоста (GitHub Runner)
git-mini-clone() {
    local REPO="$1"
    local COMMIT="$2"
    local TARGET="${3:-.}"
    echo "Cloning $REPO ($COMMIT) into $TARGET..."
    git clone --filter=blob:none --quiet "$REPO" "$TARGET"
    if [[ -n "$COMMIT" ]]; then
        ( cd "$TARGET" && git checkout --quiet "$COMMIT" )
    fi
}
export -f git-mini-clone

echo "Downloading sources..."

mapfile -t STAGES < <(find scripts.d -name "*.sh" | sort)

for STAGE in "${STAGES[@]}"; do
    [[ -f "$STAGE" ]] || continue
    unset SCRIPT_REPO SCRIPT_COMMIT SCRIPT_REPO2 SCRIPT_COMMIT2
    
    STAGENAME="$(basename "$STAGE" | sed 's/.sh$//')"
    
    # Проверка включенности
    if ! ( source "$STAGE" && ffbuild_enabled ); then continue; fi
    
    # Получаем команду загрузки
    DL_COMMAND=$( ( source "$STAGE" && ffbuild_dockerdl ) )
    [[ -z "$DL_COMMAND" ]] && continue
    
    # Удаляем retry-tool, если он есть в строке
    DL_COMMAND="${DL_COMMAND//retry-tool /}"
    
    DL_HASH="$(echo "$DL_COMMAND" | sha256sum | cut -d" " -f1)"
    TGT_FILE="${DL_DIR}/${STAGENAME}_${DL_HASH}.tar.xz"
    LATEST_LINK="${DL_DIR}/${STAGENAME}.tar.xz"

    if [[ -f "$TGT_FILE" ]]; then
        echo "Cache hit for $STAGENAME"
        ln -sf "$(basename "$TGT_FILE")" "$LATEST_LINK"
        continue
    fi

    echo "Downloading $STAGENAME..."
    WORK_DIR=$(mktemp -d)
    
    # Выполняем загрузку, прокидывая нашу функцию эмуляции
    if ( cd "$WORK_DIR" && eval "$DL_COMMAND" ); then
        tar -cpJf "$TGT_FILE" -C "$WORK_DIR" .
        ln -sf "$(basename "$TGT_FILE")" "$LATEST_LINK"
    else
        echo "Failed to download $STAGENAME."
        rm -rf "$WORK_DIR"
        exit 1
    fi
    rm -rf "$WORK_DIR"
done
