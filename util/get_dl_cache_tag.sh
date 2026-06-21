#!/bin/bash

set -eo pipefail
cd "$(dirname "$0")/.."

# Explicitly source vars to ensure we get the right values
# This ensures the cache key is consistent regardless of environment
source util/vars.sh "${TARGET:-win64}" "${VARIANT:-nonfree}" 2>/dev/null || {
    echo "ERROR: Could not source vars.sh" >&2
    exit 1
}

# State depends on:
# - Target and variant
# - FFmpeg repo and branch
# - All build scripts and patches (sorted deterministically)

{
    echo "${TARGET}-${VARIANT}"
    echo "${FFMPEG_REPO:-https://git.ffmpeg.org/ffmpeg.git}-${FFMPEG_BRANCH:-master}"
    find scripts.d patches -type f \( -name "*.sh" -o -name "*.patch" \) 2>/dev/null | sort
} > cache_state.tmp

sha256sum cache_state.tmp | cut -d" " -f1 | cut -c1-16
rm -f cache_state.tmp