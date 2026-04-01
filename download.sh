#!/bin/bash

set -e

cd "$(dirname "$0")"

# фикс проблем с git 
git config --global advice.detachedHead false
git config --global core.autocrlf false
git config --global --add safe.directory "*"
# Если скорость ниже 1Кб/сек в течение 30 секунд — обрываем соединение
git config --global http.lowSpeedLimit 1000
git config --global http.lowSpeedTime 30
# Увеличиваем буфер для тяжелых объектов (актуально для ffmpeg/torch)
git config --global http.postBuffer 524288000

source util/vars.sh "$TARGET" "$VARIANT" \
    || { echo "ERROR: vars.sh failed. TARGET=$TARGET VARIANT=$VARIANT" >&2; exit 1; }
source util/dl_functions.sh

JOBLOG=$(mktemp)

# очистка временной папки и файлов
trap 'rm -f "$JOBLOG"; rm -rf "$TMP_DIR"' EXIT

if [[ ! -d "$CACHE_DIR" ]]; then
    log_warn "Cache directory $CACHE_DIR not found!"
    exit 0
else
    log_debug "${DIRS_MARK} Current Cache directory is:\n$CACHE_DIR"
fi

log_info "${DOWN_MARK} Starting parallel downloads for $TARGET-$VARIANT..."
# If ONLY_STAGE is set, only download matching stages
if [[ -n "$ONLY_STAGE" ]]; then
    STAGES=$(find scripts.d -name "*.sh" | sort | grep -E "$ONLY_STAGE")
else
    STAGES=$(find scripts.d -name "*.sh" | sort)
fi

# --halt now,fail=1 меняем на --halt soon,fail=20%; (--line-buffer may be useful)
# Это даст шанс остальным докачаться, даже если один упал
echo "$STAGES" | parallel --halt now,fail=1 --jobs 8 \
    --joblog "$JOBLOG" \
    --group \
    "export TARGET='$TARGET'; \
     export VARIANT='$VARIANT'; \
     export ROOT_DIR='$ROOT_DIR'; \
     source '$UTIL_DIR/vars.sh' \$TARGET \$VARIANT 2>/dev/null \
         || { echo 'ERROR: vars.sh failed in parallel job' >&2; exit 1; }; \
     source '$UTIL_DIR/dl_functions.sh'; \
     download_stage {} '$CACHE_DIR'"

if [[ -f "$JOBLOG" ]]; then
    # Извлекаем список команд ($NF) для строк, где статус ($7) не равен 0
    failed=$(awk 'NR>1 && $7 != 0 {print $NF}' "$JOBLOG")
    [[ -n "$failed" ]] && log_error "Failed downloads:\n$failed"
fi

log_info "${CHECK_MARK} All sequential downloads finished successfully."
log_info "${SEARCH_MARK} Checking for FFmpeg updates..."

# Получаем хеш последнего коммита в удаленной ветке (без клонирования)
REMOTE_HASH=$(git ls-remote "$FFMPEG_REPO" "refs/heads/$FFMPEG_BRANCH" | cut -f1)
if [[ -z "$REMOTE_HASH" ]]; then
    log_error "Failed to fetch remote hash for $FFMPEG_REPO"
    # Если не удалось проверить, но папка есть - работаем с тем, что есть
    [[ ! -d "$FFMPEG_DIR/.git" ]] && exit 1
else
    # Читаем локальный хеш (если файл существует)
    LOCAL_HASH=$(cat "$FFMPEG_HASH_FILE" 2>/dev/null || echo "none")
    if [[ "$REMOTE_HASH" == "$LOCAL_HASH" && -d "$FFMPEG_DIR/configure" ]]; then
        log_info "${CHECK_MARK} FFmpeg is up to date (Commit: ${REMOTE_HASH:0:7}). Skipping download."
    else
        log_warn "${DOWN_MARK} New version detected or source missing. ${SYNC_MARK} Fetching FFmpeg..."
        # FFmpeg update (--quiet для чистоты логов)
        # Используем переменные FFMPEG_REPO и FFMPEG_BRANCH из workflow.yaml
        if [[ ! -d "$FFMPEG_DIR/.git" ]]; then
            mkdir -p "$FFMPEG_DIR"
            log_info "${DOWN_MARK} Cloning FFmpeg from $FFMPEG_REPO ($FFMPEG_BRANCH)"
            git clone --progress --depth=1 --branch="$FFMPEG_BRANCH" "$FFMPEG_REPO" "$FFMPEG_DIR" 2>&1 | pv -l -q -p | log_debug "Cloning..."
        else
            ( cd "$FFMPEG_DIR" && \
              git remote set-url origin "$FFMPEG_REPO" && \
              git fetch --quiet --depth=1 origin "$FFMPEG_BRANCH" && \
              git reset --hard FETCH_HEAD && \
              git clean -df )
        fi
        # Сохраняем новый хеш после успешного обновления
        echo "$REMOTE_HASH" > "$FFMPEG_HASH_FILE"
        log_info "${CHECK_MARK} FFmpeg updated to: ${REMOTE_HASH:0:7}"
    fi
fi

log_info "${CHECK_MARK} All downloads finished."

exit 0