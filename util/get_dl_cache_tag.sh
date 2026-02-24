#!/bin/bash
set -eo pipefail
cd "$(dirname "$0")/.."

# Состояние кэша зависит только от:
# Списка файлов (если добавили новый скрипт - кэш обновится)
# Названия таргета и варианта
# Версии FFmpeg (так как она качается отдельно в .cache/ffmpeg)

{
    echo "$TARGET-$VARIANT"
    echo "$FFMPEG_REPO-$FFMPEG_BRANCH"
    find scripts.d patches -type f -name "*.sh" -o -name "*.patch" | sort
} > cache_state.tmp

sha256sum cache_state.tmp | cut -d" " -f1 | cut -c1-16
rm cache_state.tmp
