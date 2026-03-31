#!/bin/bash

set -e

# фикс проблем с git 
git config --global advice.detachedHead false
git config --global core.autocrlf false
git config --global --add safe.directory "*"
# Если скорость ниже 1Кб/сек в течение 30 секунд — обрываем соединение
git config --global http.lowSpeedLimit 1000
git config --global http.lowSpeedTime 30
# Увеличиваем буфер для тяжелых объектов (актуально для ffmpeg/torch)
git config --global http.postBuffer 524288000

cd "$(dirname "$0")"

export ROOT_DIR="$PWD"

source util/vars.sh "$TARGET" "$VARIANT" \
    || { echo "ERROR: vars.sh failed. TARGET=$TARGET VARIANT=$VARIANT" >&2; exit 1; }
source util/dl_functions.sh

mkdir -p .cache/downloads
DL_DIR="$PWD/.cache/downloads"
JOBLOG=$(mktemp)

# очистка временной папки и файлов
trap 'rm -f "$JOBLOG"; rm -rf .cache/tmp' EXIT

if [[ ! -d "$DL_DIR" ]]; then
    log_warn "Cache directory $DL_DIR not found!"
    exit 0
else
    log_debug "${DIRS_MARK} Current Cache directory is:\n$DL_DIR"
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
    --tag \
    --group \
    --bar \
    "export TARGET='$TARGET'; \
     export VARIANT='$VARIANT'; \
     export ROOT_DIR='$ROOT_DIR'; \
     source '$ROOT_DIR/util/vars.sh' \$TARGET \$VARIANT 2>/dev/null \
         || { echo 'ERROR: vars.sh failed in parallel job' >&2; exit 1; }; \
     source '$ROOT_DIR/util/dl_functions.sh'; \
     download_stage {} '$DL_DIR'"

if [[ -f "$JOBLOG" ]]; then
    # Извлекаем список команд ($NF) для строк, где статус ($7) не равен 0
    failed=$(awk 'NR>1 && $7 != 0 {print $NF}' "$JOBLOG")
    [[ -n "$failed" ]] && log_error "Failed downloads:\n$failed"
fi

log_info "${CHECK_MARK} All sequential downloads finished successfully."

# FFmpeg update (добавил --quiet для чистоты логов)
FFMPEG_DIR=".cache/ffmpeg"
mkdir -p "$FFMPEG_DIR"
# Используем переменные из workflow.yaml
REPO_URL="${FFMPEG_REPO}"
BRANCH_NAME="${FFMPEG_BRANCH}"

if [[ ! -d "$FFMPEG_DIR/.git" ]]; then
    log_info "${DOWN_MARK} Cloning FFmpeg from $REPO_URL ($BRANCH_NAME)"
    git clone --quiet --depth=1 --branch="$BRANCH_NAME" "$REPO_URL" "$FFMPEG_DIR"
else
    git -C "$FFMPEG_DIR" status >/dev/null 2>&1 || rm -rf "$FFMPEG_DIR"
    log_info "${SYNC_MARK} Updating FFmpeg from $REPO_URL"
    ( cd "$FFMPEG_DIR" && \
      git remote set-url origin "$REPO_URL" && \
      git fetch --quiet --depth=1 origin "$BRANCH_NAME" && \
      git reset --hard FETCH_HEAD )
fi
log_info "${CHECK_MARK} All downloads finished."

exit 0