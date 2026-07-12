#!/bin/bash

set -eo pipefail

cd "$(dirname "$0")/.."

source util/vars.sh "${TARGET:-win64}" "${VARIANT:-nonfree}" 2>/dev/null || {
    echo "ERROR: Could not source vars.sh" >&2
    exit 1
}

# State depends on:
# - Target and variant
# - FFmpeg repo and branch
# - All build scripts and patches (sorted deterministically)

MODE="${1:-deps}" # By default, we calculate the hash for dependencies

# A helper function for normalizing file contents before hashing.
# It strips comments, empty lines, trailing spaces, and \r characters.
normalize_and_hash() {
    local file_path="$1"
    grep -v '^[[:space:]]*#' "$file_path" 2>/dev/null \
        | sed -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//' \
        | grep -v '^[[:space:]]*$' \
        | tr -d '\r' | sha256sum | cut -d" " -f1
}

if [[ "$MODE" == "ffmpeg" ]]; then
    # HASH FOR FFMPEG ONLY
    {
        echo "${FFMPEG_REPO:-https://git.ffmpeg.org/ffmpeg.git}-${FFMPEG_BRANCH:-master}"

        if [[ -d "patches/ffmpeg" ]]; then
            # take patches only from the ffmpeg folder
            find patches/ffmpeg -type f 2>/dev/null | sort | while read -r patch_file; do
                p_hash=$(normalize_and_hash "$patch_file")
                echo "$p_hash  $patch_file"
            done
        fi
    } > cache_state.tmp
else
    # HASH FOR THIRD-PARTY LIBRARIES (deps)
    {
        echo "${TARGET}-${VARIANT}"

        # Scan and normalize scripts in scripts.d
        find scripts.d -type f -name "*.sh" 2>/dev/null | sort | while read -r script_file; do
            s_hash=$(normalize_and_hash "$script_file")
            echo "$s_hash  $script_file"
        done

        # Scan scripts.d and ALL patches EXCEPT the patches/ffmpeg folder
        if [[ -d "patches" ]]; then
            find patches -type f -name "*.patch" ! -path "patches/ffmpeg/*" 2>/dev/null | sort | while read -r patch_file; do
                p_hash=$(normalize_and_hash "$patch_file")
                echo "$p_hash  $patch_file"
            done
        fi
    } > cache_state.tmp
fi

# Calculate the final 16-character hash of the state
sha256sum cache_state.tmp | cut -d" " -f1 | cut -c1-16
rm -f cache_state.tmp

# old
# All build scripts and patches (sorted deterministically)
# find scripts.d patches -type f \( -name "*.sh" -o -name "*.patch" \) 2>/dev/null | sort
