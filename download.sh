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

# Функция для обработки ОДНОГО скрипта (экспортируем для xargs)
download_stage() {
    local STAGE="$1"
    local TARGET="$2"
    local VARIANT="$3"
    local DL_DIR="$4"
    
    STAGENAME="$(basename "$STAGE" | sed 's/.sh$//')"

    # Запускаем в чистом subshell, чтобы переменные одного скрипта не влияли на другой
    DL_COMMAND=$(bash -c "source util/vars.sh \"$TARGET\" \"$VARIANT\" &>/dev/null; source util/dl_functions.sh; source \"$STAGE\"; ffbuild_enabled && ffbuild_dockerdl" || echo "")
    
    [[ -z "$DL_COMMAND" ]] && return 0
    
    # Очистка команды
    DL_COMMAND="${DL_COMMAND//retry-tool /}"
    DL_COMMAND="${DL_COMMAND//git fetch --unshallow/true}"
    
    DL_HASH="$(echo "$DL_COMMAND" | sha256sum | cut -d" " -f1)"
    TGT_FILE="${DL_DIR}/${STAGENAME}_${DL_HASH}.tar.xz"
    LATEST_LINK="${DL_DIR}/${STAGENAME}.tar.xz"

    # ЛОГИКА КЭША
    if [[ -f "$TGT_FILE" ]]; then
        echo "Cache hit: $STAGENAME"
        ln -sf "$(basename "$TGT_FILE")" "$LATEST_LINK"
        # Проверка валидности (важно для RO-маунтов в Docker)
        [[ -e "$LATEST_LINK" ]] && return 0 || echo "Symlink broken, re-downloading..."
    fi

    echo "Downloading: $STAGENAME..."
    WORK_DIR=$(mktemp -d)
    
    if ( cd "$WORK_DIR" && eval "$DL_COMMAND" ); then
        # Упаковка
        tar -cpJf "$TGT_FILE" -C "$WORK_DIR" .
        
        # СОЗДАНИЕ СИМЛИНКА (теперь внутри блока успеха)
        ln -sf "$(basename "$TGT_FILE")" "$LATEST_LINK"
        
        if [[ -e "$LATEST_LINK" ]]; then
            echo "Done: $STAGENAME (Link: $(basename "$TGT_FILE"))"
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
export -f git-mini-clone

echo "Starting parallel downloads for $TARGET-$VARIANT..."

# Находим все включенные скрипты и запускаем в 8 потоков
# Если два скрипта (например, 45-vulkan-loader.sh и 40-vulkan-headers.sh) имеют одинаковую команду загрузки (один и тот же репозиторий и коммит), они могут попытаться писать в один и тот же временный файл или конфликтовать. Но благодаря mktemp -d в download.sh это безопасно.
find scripts.d -name "*.sh" | sort | \
    xargs -I{} -P 8 bash -c "download_stage '{}' '$TARGET' '$VARIANT' '$DL_DIR'"

echo "All downloads finished."

# не будем упаковывать FFmpeg в .tar.xz, а просто оставим в папке .cache/ffmpeg
FFMPEG_REPO="${FFMPEG_REPO:-https://github.com/MartinEesmaa/FFmpeg.git}"
FFMPEG_BRANCH="${GIT_BRANCH:-master}"
FFMPEG_DIR=".cache/ffmpeg"
mkdir -p "$FFMPEG_DIR" # ГАРАНТИРУЕМ, ЧТО ПАПКА СУЩЕСТВУЕТ ДЛЯ DOCKER
if [[ ! -d "$FFMPEG_DIR/.git" ]]; then
    echo "Cloning FFmpeg ($FFMPEG_BRANCH)..."
    git clone --filter=blob:none --depth=1 --branch="$FFMPEG_BRANCH" "$FFMPEG_REPO" "$FFMPEG_DIR"
else
    echo "Updating FFmpeg..."
    ( cd "$FFMPEG_DIR" && git fetch --depth=1 origin "$FFMPEG_BRANCH" && git reset --hard FETCH_HEAD )
fi
