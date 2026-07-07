#!/bin/bash

set -e
# set -xe

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

# We ONLY look at the actual .git folder. We DO NOT read the .current_commit file yet.
LOCAL_HASH="none"
LOCAL_VALID=false

if [[ -d "$FFMPEG_DIR/.git" ]]; then
    # Run git rev-parse INSIDE the directory to get the REAL current hash
    cd "$FFMPEG_DIR"
    HASH_FROM_GIT=$(git rev-parse HEAD 2>/dev/null)
    if [[ -n "$HASH_FROM_GIT" ]]; then
        LOCAL_HASH="$HASH_FROM_GIT"
        LOCAL_VALID=true
        [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]] && log_debug "Local .git folder valid. Hash: ${LOCAL_HASH:0:7}"
    else
        log_warn "Local .git folder exists but is corrupted (empty HEAD). Resetting."
        rm -rf "$FFMPEG_DIR/.git" # Remove bad git data, keep source files
    fi
fi

# FALLBACK: Check FFmpeg Hash File if .git is missing or invalid
# This happens if the cache restored files but missed the .git folder
if [[ "$LOCAL_VALID" == "false" ]]; then
    if [[ -f "$FFMPEG_HASH_FILE" ]]; then
        FILE_HASH=$(cat "$FFMPEG_HASH_FILE" 2>/dev/null)
        if [[ -n "$FILE_HASH" && ${#FILE_HASH} -ge 7 ]]; then
            [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]] && log_debug "Local .git missing. Using hash from file: ${FILE_HASH:0:7}"
            LOCAL_HASH="$FILE_HASH"
            # We assume the files are valid if the hash matches the expected remote
            # We cannot verify with git, but we can proceed if hashes match
            log_warn "Running in 'File-Only' mode. Git verification skipped."
        fi
    else
        log_debug "No .git folder and no hash file found."
    fi
fi

# 3. Get the hash of the last commit in the remote branch (without cloning)
REMOTE_HASH=$(git ls-remote "$FFMPEG_REPO" "refs/heads/$FFMPEG_BRANCH" | cut -f1)

if [[ -z "$REMOTE_HASH" ]]; then
    log_error "Failed to fetch remote hash for $FFMPEG_REPO"
    # If we have a local hash (from file), we might proceed, but it's risky
    if [[ "$LOCAL_HASH" == "none" ]]; then
        exit 1
    fi
    log_warn "Remote unreachable. Proceeding with cached version: ${LOCAL_HASH:0:7}"
else
    # 4. VISUAL COMPARISON
    if [[ "$LOCAL_HASH" != "none" ]]; then
        separator_box "─" "HASH COMPARISON" "top"
        if [[ "$LOCAL_HASH" == "$REMOTE_HASH" ]]; then
            printf '  %-8s  %b%s%b\n' "local"  "$LOG_INFO"  "${LOCAL_HASH:0:12}"  "$NC" >&2
            printf '  %-8s  %b%s%b\n' "remote" "$LOG_INFO"  "${REMOTE_HASH:0:12}" "$NC" >&2
            printf '  %-8s  %b%s%b\n' "status" "$LOG_INFO"  "✔ up to date"        "$NC" >&2
        else
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
            printf '  %-8s  %b%s%b\n' "status" "$LOG_WARN" "⚠️ update needed" "$NC" >&2
        fi
        separator_box "─" "" "bottom"
    fi

    # 5. EXECUTION LOGIC
    # Case A: Hashes match and we have a valid .git -> Perfect Skip
    if [[ "$LOCAL_HASH" == "$REMOTE_HASH" && "$LOCAL_VALID" == "true" && -f "$FFMPEG_DIR/configure" ]]; then
        log_info "${CHECK_MARK} FFmpeg is up to date (Commit: ${REMOTE_HASH:0:7}). Skipping."
        
    # Case B: Hashes match, but we only have the file (no .git) -> Safe Skip (Assume valid)
    elif [[ "$LOCAL_HASH" == "$REMOTE_HASH" && "$LOCAL_VALID" == "false" && -f "$FFMPEG_DIR/configure" ]]; then
        log_info "${CHECK_MARK} FFmpeg matches remote (${REMOTE_HASH:0:7}). Skipping (File-only mode)."
        
    # Case C: Update disabled -> Use whatever we have
    elif [[ "${FFMPEG_UPDATE:-1}" == "0" ]]; then
        if [[ "$LOCAL_HASH" == "none" ]]; then
            log_error "FFmpeg update disabled but no source found."
            exit 1
        fi
        log_warn "Updates disabled. Using cached version: ${LOCAL_HASH:0:7}"
        
    # Case D: Need to update or clone
    else
        if [[ "$LOCAL_HASH" == "none" ]]; then
            # Case D1: No cache at all -> Full Clone
            log_warn "No local cache found. Cloning fresh..."
            rm -rf "$FFMPEG_DIR"
            mkdir -p "$FFMPEG_DIR"
            git clone --progress --depth=1 --branch="$FFMPEG_BRANCH" \
                "$FFMPEG_REPO" "$FFMPEG_DIR" 2>&1 | while IFS= read -r line; do log_debug "$line"; done
            
            if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
                log_error "git clone failed."
                rm -rf "$FFMPEG_DIR"
                exit 1
            fi
            log_info "${CHECK_MARK} FFmpeg cloned to: $(cd "$FFMPEG_DIR" && git rev-parse HEAD | cut -c1-7)"
            
        else
            # Case D2: Cache exists but is old OR .git is missing but hash file exists
            # If .git is missing, we MUST re-clone or re-init.
            if [[ "$LOCAL_VALID" == "false" ]]; then
                log_warn "Hash file found but .git missing. Re-cloning to restore git metadata..."
                rm -rf "$FFMPEG_DIR"
                mkdir -p "$FFMPEG_DIR"
                git clone --progress --depth=1 --branch="$FFMPEG_BRANCH" \
                    "$FFMPEG_REPO" "$FFMPEG_DIR" 2>&1 | while IFS= read -r line; do log_debug "$line"; done
            else
                # .git exists but is old -> Fast Update
                log_warn "Cache exists but stale. Updating ${LOCAL_HASH:0:7} → ${REMOTE_HASH:0:7}..."
                [[ -f "$FFMPEG_DIR/.git/index.lock" ]] && rm -f "$FFMPEG_DIR/.git/index.lock"
                ( cd "$FFMPEG_DIR" && \
                  git remote set-url origin "$FFMPEG_REPO" && \
                  git fetch --quiet --depth=1 --force origin "refs/heads/$FFMPEG_BRANCH:refs/remotes/origin/$FFMPEG_BRANCH" && \
                  git reset --hard FETCH_HEAD && \
                  git clean -df ) 2>&1 | while IFS= read -r line; do log_debug "$line"; done
            fi

            if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
                log_error "git update/clone failed."
                exit 1
            fi
            log_info "${CHECK_MARK} FFmpeg updated to: $(cd "$FFMPEG_DIR" && git rev-parse HEAD | cut -c1-7)"
        fi
    fi
fi

# 6. SAVE THE CURRENT HASH
# We write the ACTUAL current hash (from the directory) to the file.
if [[ -d "$FFMPEG_DIR/.git" ]]; then
    cd "$FFMPEG_DIR"
    ACTUAL_HASH=$(git rev-parse HEAD 2>/dev/null)
    echo "$ACTUAL_HASH" > "$FFMPEG_HASH_FILE"
    [[ "${FFBUILD_VERBOSE:-0}" -ge 1 ]] && log_debug "Saved current commit to $FFMPEG_HASH_FILE: ${ACTUAL_HASH:0:7}"
fi

phase_footer "✔ All downloads completed."

exit 0