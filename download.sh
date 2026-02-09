#!/bin/bash
set -e
cd "$(dirname "$0")"

# Подгружаем переменные и функции
source util/vars.sh "$TARGET" "$VARIANT" || true
source util/dl_functions.sh

mkdir -p .cache/downloads
DL_DIR="$PWD/.cache/downloads"

git-mini-clone() {
    local REPO="$1"
    local COMMIT="$2"
    local TARGET_DIR="${3:-.}"
    [[ "$TARGET_DIR" == "." ]] && TARGET_DIR="./"
    echo "Cloning $REPO ($COMMIT) into $TARGET_DIR..."
    git clone --filter=blob:none --quiet "$REPO" "$TARGET_DIR"
    if [[ -n "$COMMIT" && "$COMMIT" != "master" && "$COMMIT" != "main" ]]; then
        ( cd "$TARGET_DIR" && git checkout --quiet "$COMMIT" )
    fi
}

# single thread
# echo "Downloading sources for TARGET=$TARGET VARIANT=$VARIANT..."
# mapfile -t STAGES < <(find scripts.d -name "*.sh" | sort)

# Функция для обработки ОДНОГО скрипта (экспортируем для xargs)
download_stage() {
    local STAGE="$1"
    local TARGET="$2"
    local VARIANT="$3"
    local DL_DIR="$4"
    
    STAGENAME="$(basename "$STAGE" | sed 's/.sh$//')"

    # Очищаем переменные
    # unset SCRIPT_REPO SCRIPT_COMMIT SCRIPT_REPO2 SCRIPT_COMMIT2

    # Получаем команду, подавляя выход всего скрипта при ошибке в subshell
    DL_COMMAND=$(bash -c "source util/vars.sh \"$TARGET\" \"$VARIANT\" &>/dev/null; source util/dl_functions.sh; source \"$STAGE\"; ffbuild_enabled && ffbuild_dockerdl" || echo "")
    
    [[ -z "$DL_COMMAND" ]] && return 0
    
    # Очистка команды
    DL_COMMAND="${DL_COMMAND//retry-tool /}"
    DL_COMMAND="${DL_COMMAND//git fetch --unshallow/true}"
    
    DL_HASH="$(echo "$DL_COMMAND" | sha256sum | cut -d" " -f1)"
    TGT_FILE="${DL_DIR}/${STAGENAME}_${DL_HASH}.tar.xz"
    LATEST_LINK="${DL_DIR}/${STAGENAME}.tar.xz"

    if [[ -f "$TGT_FILE" ]]; then
        echo "Cache hit: $STAGENAME"
        ln -sf "$(basename "$TGT_FILE")" "$LATEST_LINK"
        return 0
    fi

    echo "Downloading: $STAGENAME..."
    WORK_DIR=$(mktemp -d)
    if ( cd "$WORK_DIR" && eval "$DL_COMMAND" ); then
    # if ( cd "$WORK_DIR" && eval "$DL_COMMAND" ) >/dev/null 2>&1; then
        tar -cpJf "$TGT_FILE" -C "$WORK_DIR" .
        ln -sf "$(basename "$TGT_FILE")" "$LATEST_LINK"
        echo "Done: $STAGENAME"
    else
        echo "FAILED: $STAGENAME"
        rm -rf "$WORK_DIR"
        return 1
    fi
    rm -rf "$WORK_DIR"
}

export -f download_stage
export -f git-mini-clone

echo "Starting parallel downloads for $TARGET-$VARIANT..."

# Находим все включенные скрипты и запускаем в 8 потоков
find scripts.d -name "*.sh" | sort | \
    xargs -I{} -P 8 bash -c "download_stage '{}' '$TARGET' '$VARIANT' '$DL_DIR'"

echo "All downloads finished."
