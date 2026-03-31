#!/bin/bash

set -e
shopt -s globstar

CLEAN_TARGET=$(echo "${1:-$TARGET}" | awk '{print $1}')
CLEAN_VARIANT=$(echo "${2:-$VARIANT}" | awk '{print $1}')
CLEAN_INACTIVE=${CLEAN_INACTIVE:-0}

if [[ -z "$CLEAN_TARGET" || -z "$CLEAN_VARIANT" ]]; then
    echo "ERROR: Cleanup aborted. TARGET and VARIANT must be specified." >&2
    echo "Usage: ./clean_cache.sh <target> <variant>" >&2
    exit 1
fi

if ! source "$(dirname "$0")/vars.sh" "$CLEAN_TARGET" "$CLEAN_VARIANT" 2>/dev/null; then
    echo "ERROR: Failed to source vars.sh for $CLEAN_TARGET-$CLEAN_VARIANT" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/../.cache/downloads"
SCRIPTS_DIR="$SCRIPT_DIR/../scripts.d"

if [[ ! -d "$CACHE_DIR" ]]; then
    log_warn "Cache directory $CACHE_DIR not found. Nothing to clean."
    exit 0
else
    log_debug "${DIRS_MARK} Current Cache directory is:\n$CACHE_DIR"
fi

log_info "${BROOM_MARK} Starting smart cleanup in Cache directory..."
[[ "$CLEAN_INACTIVE" == "1" ]] && log_info "${XCLAM_MARK} Source Cache clearing for inactive components is enabled!" || log_info "${XCLAM_MARK} Source Cache clearing for inactive components is not active." 

# Build the protected-files list
RAW_KEEP_LIST=$(mktemp)
FINAL_KEEP_LIST=$(mktemp)
trap 'rm -f "$RAW_KEEP_LIST" "$FINAL_KEEP_LIST"' EXIT

# Counters for the summary line
count_active_enabled=0
count_inactive_kept=0
count_skipped=0

for STAGE in "$SCRIPTS_DIR"/**/*.sh; do
    [[ -f "$STAGE" ]] || continue
    STAGENAME="$(basename "$STAGE" .sh)"

    # Is this stage active (listed in ONLY_STAGE)?
    is_active=false
    if [[ -z "$ONLY_STAGE" ]]; then
        is_active=true
    elif [[ "$STAGENAME" =~ ^($ONLY_STAGE)$ ]] || \
         [[ "$ONLY_STAGE" =~ (^|\|)$STAGENAME($|\|) ]]; then
        is_active=true
    fi

    # Is this stage enabled (ffbuild_enabled returns 0)?
    is_enabled=false
    if ( set +e
         source "$(dirname "$0")/vars.sh" "$CLEAN_TARGET" "$CLEAN_VARIANT" >/dev/null 2>&1
         source "$STAGE" >/dev/null 2>&1
         ffbuild_enabled >/dev/null 2>&1 ); then
        is_enabled=true
    fi

    # Decision tree (matches spec exactly)
    #
    #  Active + Enabled   → ALWAYS PROTECT
    #  Active + Disabled  → never protect
    #  Inactive + Enabled + CLEAN_INACTIVE=0 → PROTECT
    #  Inactive + Enabled + CLEAN_INACTIVE=1 → never protect
    #  Inactive + Disabled                   → never protect

    should_protect=false
    reason=""

    if [[ "$is_active" == "true" ]]; then
        if [[ "$is_enabled" == "true" ]]; then
            should_protect=true
            reason="active+enabled"
            count_active_enabled=$((count_active_enabled + 1))
        else
            reason="active+disabled → skip"
            count_skipped=$((count_skipped + 1))
        fi
    else
        # inactive
        if [[ "$is_enabled" == "true" ]] && [[ "$CLEAN_INACTIVE" == "0" ]]; then
            should_protect=true
            reason="inactive+enabled+keep"
            count_inactive_kept=$((count_inactive_kept + 1))
        else
            reason="inactive → skip (CLEAN_INACTIVE=${CLEAN_INACTIVE})"
            count_skipped=$((count_skipped + 1))
        fi
    fi

    # Add to keep-list if protecting
    if [[ "$should_protect" == "true" ]]; then
        DL_HASH=$(get_stage_hash "$STAGE")
        if [[ -n "$DL_HASH" ]]; then
            echo "${STAGENAME}_${DL_HASH}.tar.zst" >> "$RAW_KEEP_LIST"
            echo "${STAGENAME}.tar.zst"             >> "$RAW_KEEP_LIST"
            # Single-line debug: only shown when FFBUILD_VERBOSE >= 2 or similar
            # Use log_debug sparingly one line per protected file is too noisy at scale
        fi
    fi
    # Verbose trace only if explicitly requested (not default FFBUILD_VERBOSE=1)
    [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]] && \
        log_debug "${STAGENAME}: is_active=${is_active} is_enabled=${is_enabled} → ${reason}"
done

# Summary of decisions (one line, not 80)
log_info "${LOCK_MARK} Protected: ${count_active_enabled} active+enabled, ${count_inactive_kept} inactive+kept, ${count_skipped} skipped."

sort -u "$RAW_KEEP_LIST" > "$FINAL_KEEP_LIST"
sed -i 's/\r//g; s/[[:space:]]*$//' "$FINAL_KEEP_LIST"

# Debug: show keep-list only at verbose >= 2
if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then
    log_debug "FINAL_KEEP_LIST (first 10):"
    head -n 10 "$FINAL_KEEP_LIST" || true
fi

rm -f "$RAW_KEEP_LIST" || true

# Deletion pass

cd "$CACHE_DIR" || exit 0
mapfile -t PROTECTED_FILES < "$FINAL_KEEP_LIST"

deleted_count=0
skipped_young=0

log_info "${BROOM_MARK} Scanning Cache for orphaned/outdated files..."

for f in *.tar.zst; do
    [[ -e "$f" || -L "$f" ]] || continue

    is_protected=false
    for p in "${PROTECTED_FILES[@]}"; do
        if [[ "$f" == "$p" ]]; then
            is_protected=true
            break
        fi
    done

    [[ "$is_protected" == "true" ]] && continue

    if [[ -L "$f" ]]; then
        log_info "${BROOM_MARK} Removing obsolete symlink: $f"
        rm -f "$f"
        deleted_count=$((deleted_count + 1))
    elif [[ -f "$f" ]]; then
        # 30-minute grace period for files being actively downloaded
        if [[ -n $(find "$f" -mmin +30 2>/dev/null) ]]; then
            log_info "${BROOM_MARK} Deleting orphaned Cache file: $f"
            rm -f "$f"
            deleted_count=$((deleted_count + 1))
        else
            skipped_young=$((skipped_young + 1))
        fi
    fi
done

# Remove broken symlinks unconditionally
find . -maxdepth 1 -xtype l -delete || true

# Final summary (single line)
if [[ "$deleted_count" -eq 0 && "$skipped_young" -eq 0 ]]; then
    log_info "${CHECK_MARK} Cache is already clean. Nothing to remove."
else
    [[ "$deleted_count" -gt 0 ]] && \
        log_info "${CHECK_MARK} Cleanup finished. Removed ${deleted_count} outdated/orphaned files."
    [[ "$skipped_young" -gt 0 ]] && \
        log_info "${XCLAM_MARK} Skipped ${skipped_young} recently-modified files (< 30 min old)."
fi

exit 0