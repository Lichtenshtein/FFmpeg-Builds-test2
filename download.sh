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
    DL_COMMAND=$(bash -c "source util/vars.sh \"$TARGET\" \"$VARIANT\" &>/dev/null; \
                          source util/dl_functions.sh; \
                          source \"$STAGE\"; \
                          ffbuild_enabled && ffbuild_dockerdl" || echo "")

    [[ -z "$DL_COMMAND" ]] && return 0
    
    DL_COMMAND="${DL_COMMAND//retry-tool /}"
    DL_COMMAND="${DL_COMMAND//git fetch --unshallow/true}"
    
    # УМНЫЙ ХЭШ (Версия для глубокой отладки)
    # Берем DL_COMMAND (там сидят REPO и COMMIT)
    # Берем содержимое скрипта, но вырезаем комментарии и пустые строки
    # Это позволит менять логику сборки в ffbuild_dockerbuild и вызывать перекачку исходников
    SCRIPT_CODE=$(grep -v '^[[:space:]]*#' "$STAGE" | grep -v '^[[:space:]]*$')
    DL_HASH=$( (echo "$DL_COMMAND"; echo "$SCRIPT_CODE") | sha256sum | cut -d" " -f1 | cut -c1-16)
    
    TGT_FILE="${DL_DIR}/${STAGENAME}_${DL_HASH}.tar.zst"
    LATEST_LINK="${DL_DIR}/${STAGENAME}.tar.zst"

    # --- DEBUG SECTION ---
    log_debug "Checking cache for $STAGENAME in $DL_DIR..."
    if [[ ! -d "$DL_DIR" ]]; then
        log_error "DL_DIR ($DL_DIR) does not exist!"
    else
        log_info "Files in cache for $STAGENAME:"
        ls -F "$DL_DIR" | grep "$STAGENAME" || log_warn "No files matching $STAGENAME found"
    fi
    # ----------------------

    if [[ -f "$TGT_FILE" ]]; then
        log_info "Cache hit: $STAGENAME (File exists: $(basename "$TGT_FILE"))"
        log_info "Cache hit: $STAGENAME (Hash matched: $DL_HASH)"
        ln -sf "$(basename "$TGT_FILE")" "$LATEST_LINK"
        [[ -e "$LATEST_LINK" ]] && return 0
    else
        log_warn "Cache miss: $STAGENAME (Target file $TGT_FILE not found)"
    fi

    log_info "Downloading: $STAGENAME (Hash: $DL_HASH)..."
    # Создаем временную папку внутри проекта
    mkdir -p .cache/tmp
    WORK_DIR=$(mktemp -d -p "$ROOT_DIR/.cache/tmp")

    # ИСПОЛЬЗУЕМ АБСОЛЮТНЫЙ ПУТЬ К ФУНКЦИЯМ
    # Передаем ROOT_DIR внутрь subshell через экспорт или переменную
    if ( cd "$WORK_DIR" && eval "source \"$ROOT_DIR/util/dl_functions.sh\"; $DL_COMMAND" ); then
        find "$WORK_DIR" -name ".git*" -exec rm -rf {} +
        # -c: создать, -f: файл
        # -I 'zstd -T0 -3': -T0 задействует все ядра, -3 — оптимальный баланс скорости/сжатия
        tar -I 'zstd -T0 -3' -cf "$TGT_FILE" -C "$WORK_DIR" .
        ln -sf "$(basename "$TGT_FILE")" "$LATEST_LINK"
        if [[ -e "$LATEST_LINK" ]]; then
            log_info "Done: $STAGENAME (Name: $(basename "$TGT_FILE"))"
            rm -rf "$WORK_DIR"
            return 0
        else
            log_error "ERROR: Symlink creation failed for $STAGENAME"
            rm -rf "$WORK_DIR"
            return 1
        fi
    else
        log_error "FAILED to download $STAGENAME (Command: $DL_COMMAND)"
        rm -rf "$WORK_DIR"
        exit 1 # exit 1, чтобы xargs поймал ошибку
    fi
}

export -f download_stage

log_info "Starting parallel downloads for $TARGET-$VARIANT..."
# Внутри xargs нужно делать source util/vars.sh ПЕРЕД вызовом функции
# -n 1: обрабатывать ровно один аргумент за раз.
# --halt once,fail=1: Если хотя бы один процесс завершится с ненулевым кодом (exit 1), xargs немедленно прекратит запуск новых задач и завершит работу.
find scripts.d -name "*.sh" | sort | \
    xargs -I{} -P 8 -n 1 --halt once,fail=1 bash -c 'export TARGET="'$TARGET'"; export VARIANT="'$VARIANT'"; export ROOT_DIR="'$ROOT_DIR'"; source util/vars.sh "$TARGET" "$VARIANT" &>/dev/null; source util/dl_functions.sh; download_stage "{}" "$TARGET" "$VARIANT" "$DL_DIR"'

    # xargs -I{} -P 8 -n 1 --halt once,fail=1 bash -c "export TARGET='$TARGET'; export VARIANT='$VARIANT'; export ROOT_DIR='$ROOT_DIR'; source util/vars.sh \$TARGET \$VARIANT &>/dev/null; source util/dl_functions.sh; download_stage '{}' '$TARGET' '$VARIANT' '$DL_DIR'"

# FFmpeg update (добавил --quiet для чистоты логов)
FFMPEG_DIR=".cache/ffmpeg"
mkdir -p "$FFMPEG_DIR"
if [[ ! -d "$FFMPEG_DIR/.git" ]]; then
    git clone --quiet --filter=blob:none --depth=1 --branch="${GIT_BRANCH:-master}" "${FFMPEG_REPO:-https://github.com/MartinEesmaa/FFmpeg.git}" "$FFMPEG_DIR"
else
    log_info "Updating FFmpeg..."
    ( cd "$FFMPEG_DIR" && git fetch --quiet --depth=1 origin "${GIT_BRANCH:-master}" && git reset --hard FETCH_HEAD )
fi
log_info "All downloads finished."

# очистка временной папки
rm -rf .cache/tmp