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

export DL_RESULT_FILE

DL_RESULT_FILE=$(mktemp)
JOBLOG=$(mktemp)

phase_header "🡇" "SOURCE DOWNLOADS  [$TARGET-$VARIANT]"

# очистка временной папки и файлов
trap 'rm -f "$JOBLOG"; rm -rf "$TMP_DIR"' EXIT

if [[ ! -d "$CACHE_DIR" ]]; then
    log_warn "Cache directory $CACHE_DIR not found!"
    exit 0
else
    log_debug "${DIRS_MARK} Cache directory:\n$CACHE_DIR"
fi

# If ONLY_STAGE is set, only download matching stages
if [[ -n "$ONLY_STAGE" ]]; then
    STAGES=$(find scripts.d -name "*.sh" | sort | grep -E "$ONLY_STAGE")
    log_info "${XCLAM_MARK} Filtering stages by pattern:\n$ONLY_STAGE"
else
    STAGES=$(find scripts.d -name "*.sh" | sort)
fi

STAGE_COUNT=$(echo "$STAGES" | wc -l)
log_info "${DOWN_MARK} Queuing ${STAGE_COUNT} stage(s) for parallel download (jobs=8)..."
separator "-"

# ensuring DL_RESULT_FILE and UTIL_DIR paths with spaces are safe
_util_vars=$(printf '%q' "${UTIL_DIR}/vars.sh")
_util_dl=$(printf '%q' "${UTIL_DIR}/dl_functions.sh")
_dl_result=$(printf '%q' "$DL_RESULT_FILE")
_target=$(printf '%q' "$TARGET")
_variant=$(printf '%q' "$VARIANT")
# --halt now,fail=1 меняем на --halt soon,fail=20%;
# Это даст шанс остальным докачаться, даже если один упал
echo "$STAGES" | parallel \
--halt now,fail=1 \
--jobs 8 \
--joblog "$JOBLOG" \
--group \
"export TARGET=${_target}; \
export VARIANT=${_variant}; \
export DL_RESULT_FILE=${_dl_result}; \
source ${_util_vars} ${_target} ${_variant} 2>/dev/null \
|| { echo 'ERROR: vars.sh failed' >&2; exit 1; }; \
source ${_util_dl}; \
download_stage {}"

# Render the collected results as one aligned table after all jobs finish
render_dl_table "$DL_RESULT_FILE"
rm -f "$DL_RESULT_FILE"

if [[ -f "$JOBLOG" ]]; then
    # Извлекаем список команд ($NF) для строк, где статус ($7) не равен 0
    failed=$(awk 'NR>1 && $7 != 0 {print $NF}' "$JOBLOG")
    [[ -n "$failed" ]] && log_error "Failed downloads:\n$failed"
fi

# FFmpeg
phase_header "🔎" "FFMPEG SOURCE CHECK"

# Guard missing FFmpeg vars early
if [[ -z "${FFMPEG_REPO:-https://git.ffmpeg.org/ffmpeg.git}" || -z "${FFMPEG_BRANCH:-master}" ]]; then
    log_error "FFMPEG_REPO and FFMPEG_BRANCH must be set in the environment (workflow.yaml)"
    exit 1
fi

# Получаем хеш последнего коммита в удаленной ветке (без клонирования)
REMOTE_HASH=$(git ls-remote "$FFMPEG_REPO" "refs/heads/$FFMPEG_BRANCH" | cut -f1)
if [[ -z "$REMOTE_HASH" ]]; then
    log_error "Failed to fetch remote hash for $FFMPEG_REPO"
    # Если не удалось проверить, но папка есть - работаем с тем, что есть
    [[ ! -d "$FFMPEG_DIR/.git" ]] && exit 1
else
    # Читаем локальный хеш (если файл существует)
    LOCAL_HASH=$(cat "$FFMPEG_HASH_FILE" 2>/dev/null || echo "none")

    # Visual hash comparison
    separator_box "─" "HASH COMPARISON" "top"
    if [[ "$REMOTE_HASH" == "$LOCAL_HASH" ]]; then
        printf '  %-8s  %b%s%b\n' "local"  "$LOG_INFO"  "${LOCAL_HASH:0:12}"  "$NC" >&2
        printf '  %-8s  %b%s%b\n' "remote" "$LOG_INFO"  "${REMOTE_HASH:0:12}" "$NC" >&2
        printf '  %-8s  %b%s%b\n' "match"  "$LOG_INFO"  "✔ up to date"        "$NC" >&2
    else
        # Highlight differing characters individually
        _print_hash_diff() {
            local a="$1" b="$2" label_a="$3" label_b="$4"
            local i ca cb out_a="" out_b=""
            local len=${#a}
            for (( i=0; i<len; i++ )); do
                ca="${a:$i:1}"; cb="${b:$i:1}"
                if [[ "$ca" == "$cb" ]]; then
                    out_a+="$ca"; out_b+="$cb"
                else
                    out_a+="${LOG_WARN}${ca:-.}${NC}"
                    out_b+="${LOG_WARN}${cb:-.}${NC}"
                fi
            done
            printf '  %-8s  %b\n' "$label_a" "$out_a" >&2
            printf '  %-8s  %b\n' "$label_b" "$out_b" >&2
        }
        _print_hash_diff "$LOCAL_HASH" "$REMOTE_HASH" "local" "remote"
        printf '  %-8s  %b%s%b\n' "status" "$LOG_WARN" "⚠️ update available" "$NC" >&2
    fi
    separator_box "─" "" "bottom"

    if [[ "$REMOTE_HASH" == "$LOCAL_HASH" && -f "$FFMPEG_DIR/configure" ]]; then
        log_info "${CHECK_MARK} FFmpeg is up to date (Commit: ${REMOTE_HASH:0:7}). Skipping clone."
    else
        log_warn "New version detected or source missing. ${SYNC_MARK} Fetching FFmpeg ${FFMPEG_BRANCH} → ${REMOTE_HASH:0:7}..."
        # FFmpeg update (--quiet для чистоты логов)
        # Используем переменные FFMPEG_REPO и FFMPEG_BRANCH из workflow.yaml
        if [[ ! -d "$FFMPEG_DIR/.git" ]]; then
            # Очистка перед клонированием на случай мусора от прошлых попыток
            rm -rf "$FFMPEG_DIR"
            mkdir -p "$FFMPEG_DIR"
            git clone --progress --depth=1 --branch="$FFMPEG_BRANCH" \
                "$FFMPEG_REPO" "$FFMPEG_DIR" 2>&1 \
                | while IFS= read -r line; do log_debug "$line"; done
            if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
                log_error "git clone failed for $FFMPEG_REPO. Cleaning up..."
                rm -rf "$FFMPEG_DIR"
                exit 1
            fi
        else
            # Удаление локов перед обновлением
            [[ -f "$FFMPEG_DIR/.git/index.lock" ]] && rm -f "$FFMPEG_DIR/.git/index.lock"
            ( cd "$FFMPEG_DIR" && \
              git remote set-url origin "$FFMPEG_REPO" && \
              git fetch --quiet --depth=1 --update-shallow origin "$FFMPEG_BRANCH" && \
              git reset --hard FETCH_HEAD && \
              git clean -df && \
              git reflog expire --expire=now --all && \
              git gc --prune=now --aggressive ) 2>&1 \
                | while IFS= read -r line; do log_debug "$line"; done
            if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
                log_error "git fetch/reset failed for $FFMPEG_REPO"
                exit 1
            fi
        fi
        # Сохраняем новый хеш после успешного обновления
        echo "$REMOTE_HASH" > "$FFMPEG_HASH_FILE"
        log_info "${CHECK_MARK} FFmpeg updated to: ${REMOTE_HASH:0:7}"
        # Создаем временный файл-флаг для GitHub Actions
        touch "local_ext_cache/ffmpeg_was_updated"
    fi
fi

phase_footer "✔ All downloads completed."

exit 0