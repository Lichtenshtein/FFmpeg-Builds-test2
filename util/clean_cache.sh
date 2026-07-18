#!/bin/bash

set -o pipefail
shopt -s globstar
shopt -s nullglob

CLEAN_TARGET=$(echo "${1:-$TARGET}" | awk '{print $1}')
CLEAN_VARIANT=$(echo "${2:-$VARIANT}" | awk '{print $1}')
CLEAN_INACTIVE=${CLEAN_INACTIVE:-0}

if [[ -z "$CLEAN_TARGET" || -z "$CLEAN_VARIANT" ]]; then
    echo "ERROR: Cleanup aborted. TARGET and VARIANT must be specified." >&2
    echo "Usage: ./clean_cache.sh <target> <variant>" >&2
    exit 1
fi

if ! source "$(dirname "$0")/vars.sh" "$CLEAN_TARGET" "$CLEAN_VARIANT" 2>/dev/null; then
    echo "ERROR: Failed to source vars.sh" >&2
    exit 1
fi

log_info "${BROOM_MARK} Starting smart cleanup in cache directory..."
[[ "$CLEAN_INACTIVE" == "1" ]] && log_info "${XCLAM_MARK} Source cache clearing for inactive components is enabled!" || log_info "${XCLAM_MARK} Source cache clearing for inactive components is not active." 

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

    # Unified var derivation consistent with dl_functions.sh
    unset STAGE_HASH STAGENAME COMPONENT_NAME STAGE_CACHE_FILE STAGE_LATEST_LINK
    eval "$(stage_vars "$STAGE")"

    # Is this stage active (listed in ONLY_STAGE)?
    is_active=false
    if [[ -z "$ONLY_STAGE" ]] || [[ "|${ONLY_STAGE}|" == *"|${STAGENAME}|"* ]]; then
        is_active=true
    fi

    # Is this stage enabled (ffbuild_enabled returns 0)?
    # source vars.sh first for default ffbuild_enabled
    # then source $STAGE to get any override
    is_enabled=false
    if ( set +e
         source "${UTIL_DIR}/vars.sh" "$CLEAN_TARGET" "$CLEAN_VARIANT" >/dev/null 2>&1
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
        if [[ "$is_enabled" == "true" && "$CLEAN_INACTIVE" == "0" ]]; then
            should_protect=true
            reason="inactive+enabled+keep"
            count_inactive_kept=$((count_inactive_kept + 1))
        else
            reason="inactive → skip (CLEAN_INACTIVE=${CLEAN_INACTIVE})"
            count_skipped=$((count_skipped + 1))
        fi
    fi

    # Add to keep-list if protecting
    if [[ "$should_protect" == "true" && -n "$STAGE_HASH" ]]; then
        echo "$(basename "$STAGE_CACHE_FILE")"  >> "$RAW_KEEP_LIST"
        echo "$(basename "$STAGE_LATEST_LINK")" >> "$RAW_KEEP_LIST"
        # component's configs and options hashes
        echo "${STAGENAME}_${STAGE_HASH}.confhash" >> "$RAW_KEEP_LIST"
        echo "${STAGENAME}_${STAGE_HASH}.confopts" >> "$RAW_KEEP_LIST"
    fi

    # Verbose trace only if explicitly requested (not default FFBUILD_VERBOSE=1)
    [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]] && \
        log_debug "${STAGENAME}: active=${is_active} enabled=${is_enabled} → ${reason}"
done

# Summary of decisions (one line, not 80)
log_info "${LOCK_MARK} Protected: ${count_active_enabled} active+enabled, ${count_inactive_kept} inactive+kept, ${count_skipped} skipped."

# First fill the final list
# Build O(1) lookup set
sort -u "$RAW_KEEP_LIST" | tr -d '\r' | sed 's/[[:space:]]*$//' > "$FINAL_KEEP_LIST"

# Debug: show keep-list only at verbose >= 2
if [[ "${FFBUILD_VERBOSE:-0}" -ge 2 ]]; then
    log_debug "FINAL_KEEP_LIST (first 40):"
    head -n 40 "$FINAL_KEEP_LIST" || true
fi

declare -A PROTECTED_SET
while IFS= read -r entry; do
    [[ -n "$entry" ]] && PROTECTED_SET["$entry"]=1
done < "$FINAL_KEEP_LIST"

# Deletion pass — O(1) lookup per file
cd "$CACHE_DIR" || exit 0

deleted_count=0
skipped_young=0

log_info "${SEARCH_MARK} Scanning cache for orphaned/outdated files..."

for f in *.tar.zst; do
    [[ -e "$f" || -L "$f" ]] || continue

    if [[ -n "${PROTECTED_SET[$f]:-}" ]]; then
        continue
    fi

    if [[ -L "$f" ]]; then
        log_debug "${BROOM_MARK} Removing obsolete symlink: $f"
        rm -f "$f"
        deleted_count=$((deleted_count + 1))
    elif [[ -f "$f" ]]; then
        if [[ -n $(find "$f" -mmin +30 2>/dev/null) ]]; then
            log_debug "${BROOM_MARK} Deleting orphaned cache file: $f"
            rm -f "$f"
            deleted_count=$((deleted_count + 1))
        else
            skipped_young=$((skipped_young + 1))
        fi
    fi
done

for f in *.confhash *.confopts; do
    [[ -e "$f" ]] || continue
    [[ -n "${PROTECTED_SET[$f]:-}" ]] && continue
    log_debug "${BROOM_MARK} Removing orphaned confhash: $f"
    rm -f "$f"
    deleted_count=$((deleted_count + 1))
done

# Remove broken symlinks unconditionally
find . -maxdepth 1 -xtype l -delete || true

# Final summary (single line)
phase_header "🧹" "CACHE CLEANUP  [$CLEAN_TARGET-$CLEAN_VARIANT]"

separator_box "─" "  PROTECTION DECISIONS  " "top"
printf '  %-35s  %s\n' "CATEGORY" "COUNT" >&2
separator_box "─" "" "mid"
printf '  %-35s  %b%s%b\n' "Active + enabled (always keep)"   "$LOG_INFO"  "$count_active_enabled" "$NC" >&2
printf '  %-35s  %b%s%b\n' "Inactive + enabled (CLEAN=0 keep)" "$LOG_WARN"  "$count_inactive_kept"  "$NC" >&2
printf '  %-35s  %b%s%b\n' "Skipped (disabled or CLEAN=1)"     "$LOG_DEBUG" "$count_skipped"        "$NC" >&2
separator_box "─" "" "bottom"

if [[ "$deleted_count" -gt 0 || "$skipped_young" -gt 0 ]]; then
    separator_box "─" "  DELETION RESULTS  " "top"
    printf '  %-35s  %b%s%b\n' "Files removed"              "$LOG_WARN"  "$deleted_count"  "$NC" >&2
    printf '  %-35s  %b%s%b\n' "Skipped (< 30 min old)"     "$LOG_INFO"  "$skipped_young"  "$NC" >&2
    separator_box "─" "" "bottom"
fi

if [[ "$deleted_count" -eq 0 && "$skipped_young" -eq 0 ]]; then
    phase_footer "✔ Cache is clean — nothing removed"
else
    [[ "$deleted_count" -gt 0 ]] && \
        log_info "${CHECK_MARK} Removed ${deleted_count} outdated/orphaned file(s)"
    [[ "$skipped_young" -gt 0 ]] && \
        log_info "${XCLAM_MARK} Skipped ${skipped_young} recently-modified file(s) (< 30 min old)"
    phase_footer "✔ Cleanup complete"
fi

exit 0