#!/bin/bash
set -e

# фикс проблем с git 
git config --global advice.detachedHead false
git config --global core.autocrlf false
git config --global --add safe.directory "*"

cd "$(dirname "$0")"

export ROOT_DIR="$PWD"

source util/vars.sh "$TARGET" "$VARIANT" || true
source util/dl_functions.sh

mkdir -p .cache/downloads
DL_DIR="$PWD/.cache/downloads"

download_stage() {
    local STAGE="$1"
    local DL_DIR="$2"
    local STAGENAME=$(basename "$STAGE" .sh)

    # считаем хеш (он включает в себя вызов ffbuild_dockerdl внутри get_stage_hash)
    local DL_HASH=$(get_dl_hash "$STAGE")
    local DL_COMMANDS=$(bash -c "source util/vars.sh \"$TARGET\" \"$VARIANT\" &>/dev/null; \
                      source util/dl_functions.sh; \
                      source \"$STAGE\"; \
                      ffbuild_enabled && ffbuild_dockerdl" 2>/dev/null || echo "")

    # Если команд нет — это стадия без исходников (мета-пакет), выходим
    [[ -z "$DL_COMMANDS" ]] && return 0

    local TGT_FILE="${DL_DIR}/${STAGENAME}_${DL_HASH}.tar.zst"
    local LATEST_LINK="${DL_DIR}/${STAGENAME}.tar.zst"

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
        return 0
    else
        log_warn "Cache miss: $STAGENAME (Target file $TGT_FILE not found)"
    fi

    log_info "Downloading: $STAGENAME (Hash: $DL_HASH)..."

    # Создаем временную папку внутри проекта
    mkdir -p .cache/tmp
    WORK_DIR=$(mktemp -d -p "$ROOT_DIR/.cache/tmp")

    # сохраняем команды во временный скрипт и запускаем его
    if ( 
        cd "$WORK_DIR"
        echo "set -e" > run_dl.sh
        echo "source \"$ROOT_DIR/util/dl_functions.sh\"" >> run_dl.sh
        DL_COMMANDS="${DL_COMMANDS//retry-tool /}"
        DL_COMMANDS="${DL_COMMANDS//git fetch --unshallow/true}"
        echo "$DL_COMMANDS" >> run_dl.sh
        bash run_dl.sh
    ); then
        
        # --- КОРРЕКТНЫЙ WHITELIST ДЛЯ METADATA ---
        # glib (подмодули), x264/x265 (versioning), opus (иногда dnn fetch)
        PRESERVE_PATTERN="${GIT_PRESERVE_LIST:-glib2|x264|x265|opus|pcre2|openssl|pango|freetype|ilbc|libjxl|mbedtls|snappy|zimg|vmaf}"

        if [[ "$STAGENAME" =~ $PRESERVE_PATTERN ]]; then
            log_info "Preserving Git metadata for $STAGENAME (Whitelist match)"
        else
            log_debug "Removing Git metadata for $STAGENAME to save cache space"
            # Удаляем .git папки и .gitignore файлы
            find "$WORK_DIR" -name ".git*" -exec rm -rf {} +
        fi
        # Удаляем сам скрипт загрузки перед упаковкой
        rm -f "$WORK_DIR/run_dl.sh"
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
find scripts.d -name "*.sh" | sort | \
    # --halt now,fail=1 меняем на --halt soon,fail=20%
    # Это даст шанс остальным докачаться, даже если один упал
    parallel --halt soon,fail=20% --jobs 8 \
    "export TARGET='$TARGET'; \
     export VARIANT='$VARIANT'; \
     export ROOT_DIR='$ROOT_DIR'; \
     source util/vars.sh \$TARGET \$VARIANT &>/dev/null; \
     source util/dl_functions.sh; \
     download_stage {} '$DL_DIR'"

log_info "All sequential downloads finished successfully."

# FFmpeg update (добавил --quiet для чистоты логов)
FFMPEG_DIR=".cache/ffmpeg"
mkdir -p "$FFMPEG_DIR"
# Используем переменные из workflow.yaml
REPO_URL="${FFMPEG_REPO}"
BRANCH_NAME="${FFMPEG_BRANCH}"

if [[ ! -d "$FFMPEG_DIR/.git" ]]; then
    log_info "Cloning FFmpeg from $REPO_URL ($BRANCH_NAME)..."
    git clone --quiet --filter=blob:none --depth=1 --branch="$BRANCH_NAME" "$REPO_URL" "$FFMPEG_DIR"
else
    log_info "Updating FFmpeg from $REPO_URL..."
    ( cd "$FFMPEG_DIR" && \
      git remote set-url origin "$REPO_URL" && \
      git fetch --quiet --depth=1 origin "$BRANCH_NAME" && \
      git reset --hard FETCH_HEAD )
fi
log_info "All downloads finished."

# очистка временной папки
rm -rf .cache/tmp