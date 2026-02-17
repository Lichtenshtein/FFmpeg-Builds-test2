#!/bin/bash

# clean_cache.sh удалит старые версии либ (например, если обновился коммит в скрипте), чтобы они не занимали место в 10ГБ лимите GitHub.

set -e

cd "$(dirname "$0")/../.cache/downloads" || {
    log_warn "[WARN] Could not find .cache/downloads. Skipping cleanup."
    exit 0
}

log_info "Cleaning up orphaned cache files in $(pwd)..."

# Получаем список всех файлов, на которые указывают рабочие симлинки (STAGENAME.tar.zst)
# читаем, куда ведут симлинки, и берем только имена целевых файлов
KEEP_FILES=$(find . -maxdepth 1 -type l -name "*.tar.zst" -exec readlink {} +)

if [[ -z "$KEEP_FILES" ]]; then
    log_warn "No active symlinks found in $(pwd). Skipping cleanup to prevent accidental wipe."
    exit 0
fi

# Удаляем файлы с хешами (STAGENAME_HASH.tar.zst), которых НЕТ в списке KEEP_FILES
# Мы ищем файлы с нижним подчеркиванием в имени (хешированные архивы)
for f in *_*.tar.zst; do
    # Проверяем, есть ли этот файл в списке тех, что нужны текущим скриптам
    if ! echo "$KEEP_FILES" | grep -q "$(basename "$f")"; then
        log_info "Deleting old/unused cache: $f"
        rm -f "$f"
    fi
done

log_info "Cache cleanup finished."
