#!/bin/bash
set -e
cd "$(dirname "$0")"
source util/vars.sh "$TARGET" "$VARIANT"
source util/dl_functions.sh

mkdir -p .cache/downloads
DL_DIR="$PWD/.cache/downloads"

# Улучшенная эмуляция git-mini-clone
git-mini-clone() {
    local REPO="$1"
    local COMMIT="$2"
    local TARGET_DIR="${3:-.}"
    
    # Исправляем путь, если передана точка
    [[ "$TARGET_DIR" == "." ]] && TARGET_DIR="./"

    echo "Cloning $REPO ($COMMIT) into $TARGET_DIR..."
    
    # Используем обычный клон, но без блобов (быстро и полная история)
    git clone --filter=blob:none --quiet "$REPO" "$TARGET_DIR"
    
    if [[ -n "$COMMIT" && "$COMMIT" != "master" && "$COMMIT" != "main" ]]; then
        ( cd "$TARGET_DIR" && git checkout --quiet "$COMMIT" )
    fi
}
export -f git-mini-clone

echo "Downloading sources for TARGET=$TARGET VARIANT=$VARIANT..."

mapfile -t STAGES < <(find scripts.d -name "*.sh" | sort)

for STAGE in "${STAGES[@]}"; do

    [[ -f "$STAGE" ]] || continue
    # Сбрасываем переменные перед загрузкой, чтобы не было мусора от прошлых стадий
    unset SCRIPT_REPO SCRIPT_COMMIT SCRIPT_REPO2 SCRIPT_COMMIT2
    
    STAGENAME="$(basename "$STAGE" | sed 's/.sh$//')"

    echo "Processing $STAGENAME for $TARGET / $VARIANT"
    # ПОЛУЧАЕМ команду загрузки (теперь она точно не будет пустой)
    DL_COMMAND=$( ( 
        source ./util/vars.sh "$TARGET" "$VARIANT" && \
        source ./util/dl_functions.sh && \
        source "$STAGE" && \
        ffbuild_enabled && \
        ffbuild_dockerdl 
    ) )
    
    [[ -z "$DL_COMMAND" ]] && continue
    
    # Очистка команды
    DL_COMMAND="${DL_COMMAND//retry-tool /}"
    DL_COMMAND="${DL_COMMAND//git fetch --unshallow/true}"
    
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
    
    # Выполнение
    if ( cd "$WORK_DIR" && eval "$DL_COMMAND" ); then
        tar -cpJf "$TGT_FILE" -C "$WORK_DIR" .
        ln -sf "$(basename "$TGT_FILE")" "$LATEST_LINK"
    else
        echo "Failed to download $STAGENAME. Command was: $DL_COMMAND"
        rm -rf "$WORK_DIR"
        exit 1
    fi
    rm -rf "$WORK_DIR"
done
