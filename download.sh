#!/bin/bash
set -e
cd "$(dirname "$0")"

export ROOT_DIR="$PWD"

source util/vars.sh "$TARGET" "$VARIANT" || true
source util/dl_functions.sh

mkdir -p .cache/downloads
DL_DIR="$PWD/.cache/downloads"

download_stage() {
    local STAGE="$1"
    local TARGET="$2"
    local VARIANT="$3"
    local DL_DIR="$4"
    
    STAGENAME="$(basename "$STAGE" | sed 's/.sh$//')"

    # Получаем команду загрузки
    DL_COMMAND=$(bash -c "source util/vars.sh \"$TARGET\" \"$VARIANT\" &>/dev/null; source util/dl_functions.sh; source \"$STAGE\"; ffbuild_enabled && ffbuild_dockerdl" || echo "")
    
    [[ -z "$DL_COMMAND" ]] && return 0
    
    DL_COMMAND="${DL_COMMAND//retry-tool /}"
    DL_COMMAND="${DL_COMMAND//git fetch --unshallow/true}"
    
    # УМНЫЙ ХЭШ
    DL_HASH=$( (echo "$DL_COMMAND"; sha256sum "$STAGE") | sha256sum | cut -d" " -f1 | cut -c1-16)
    
    TGT_FILE="${DL_DIR}/${STAGENAME}_${DL_HASH}.tar.xz"
    LATEST_LINK="${DL_DIR}/${STAGENAME}.tar.xz"

    if [[ -f "$TGT_FILE" ]]; then
        echo "Cache hit: $STAGENAME (Hash: $DL_HASH)"
        ln -sf "$(basename "$TGT_FILE")" "$LATEST_LINK"
        [[ -e "$LATEST_LINK" ]] && return 0
    fi

    echo "Downloading: $STAGENAME (Hash: $DL_HASH)..."
    WORK_DIR=$(mktemp -d)
    
    # ИСПОЛЬЗУЕМ АБСОЛЮТНЫЙ ПУТЬ К ФУНКЦИЯМ
    # Передаем ROOT_DIR внутрь subshell через экспорт или переменную
    if ( cd "$WORK_DIR" && eval "source \"$ROOT_DIR/util/dl_functions.sh\"; $DL_COMMAND" ); then
        find "$WORK_DIR" -name ".git" -type d -exec rm -rf {} +
        tar -cpJf "$TGT_FILE" -C "$WORK_DIR" .
        ln -sf "$(basename "$TGT_FILE")" "$LATEST_LINK"
        if [[ -e "$LATEST_LINK" ]]; then
            echo "Done: $STAGENAME (Name: $(basename "$TGT_FILE"))"
            rm -rf "$WORK_DIR"
            return 0
        else
            echo "ERROR: Symlink creation failed for $STAGENAME"
            rm -rf "$WORK_DIR"
            return 1
        fi
    else
        echo "FAILED: $STAGENAME (Command: $DL_COMMAND)"
        rm -rf "$WORK_DIR"
        return 1
    fi
}

export -f download_stage
# git-mini-clone экспортируется автоматически, так как она в dl_functions.sh

echo "Starting parallel downloads for $TARGET-$VARIANT..."
find scripts.d -name "*.sh" | sort | \
    xargs -I{} -P 8 bash -c "ROOT_DIR='$ROOT_DIR' download_stage '{}' '$TARGET' '$VARIANT' '$DL_DIR'"

# FFmpeg update (добавил --quiet для чистоты логов)
FFMPEG_DIR=".cache/ffmpeg"
mkdir -p "$FFMPEG_DIR"
if [[ ! -d "$FFMPEG_DIR/.git" ]]; then
    git clone --quiet --filter=blob:none --depth=1 --branch="${GIT_BRANCH:-master}" "${FFMPEG_REPO:-https://github.com/MartinEesmaa/FFmpeg.git}" "$FFMPEG_DIR"
else
    echo "Updating FFmpeg..."
    ( cd "$FFMPEG_DIR" && git fetch --quiet --depth=1 origin "${GIT_BRANCH:-master}" && git reset --hard FETCH_HEAD )
fi
echo "All downloads finished."
