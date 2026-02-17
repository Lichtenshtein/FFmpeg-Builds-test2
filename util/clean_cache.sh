#!/bin/bash

# clean_cache.sh удалит старые версии либ (например, если обновился коммит в скрипте), чтобы они не занимали место в 10ГБ лимите GitHub.

set -e

# Подгружаем переменные, чтобы знать TARGET/VARIANT
source "$(dirname "$0")/vars.sh" "$TARGET" "$VARIANT" > /dev/null 2>&1

CACHE_DIR="$(dirname "$0")/../.cache/downloads"
SCRIPTS_DIR="$(dirname "$0")/../scripts.d"

if [[ ! -d "$CACHE_DIR" ]]; then
    log_warn "Cache directory $CACHE_DIR not found. Nothing to clean."
    exit 0
fi

log_info "Starting smart cleanup in $CACHE_DIR..."

# Собираем список всех актуальных хешей для активных скриптов
# Мы создадим временный список имен файлов, которые НУЖНО оставить.
KEEP_LIST=$(mktemp)

for STAGE in "$SCRIPTS_DIR"/**/*.sh; do
    [[ -e "$STAGE" ]] || continue
    
    STAGENAME="$(basename "$STAGE" | sed 's/.sh$//')"
    
    # Имитируем логику генерации хеша из download.sh
    # Это гарантирует, что мы не удалим файлы, которые download.sh только что создал
    DL_COMMAND=$(bash -c "source util/vars.sh \"$TARGET\" \"$VARIANT\" &>/dev/null; \
                          source util/dl_functions.sh; \
                          source \"$STAGE\"; \
                          ffbuild_enabled && ffbuild_dockerdl" || echo "")

    if [[ -n "$DL_COMMAND" ]]; then
        SCRIPT_CODE=$(grep -v '^[[:space:]]*#' "$STAGE" | grep -v '^[[:space:]]*$')
        DL_HASH=$( (echo "$DL_COMMAND"; echo "$SCRIPT_CODE") | sha256sum | cut -d" " -f1 | cut -c1-16)
        
        # Добавляем имя файла в список исключений для удаления
        echo "${STAGENAME}_${DL_HASH}.tar.zst" >> "$KEEP_LIST"
        log_debug "Protecting: ${STAGENAME}_${DL_HASH}.tar.zst"
    fi
done

# Проверка на "пустой список" (защита от случайной очистки всего кэша)
if [[ ! -s "$KEEP_LIST" ]]; then
    log_error "Safety trigger: No active source files identified. Refusing to delete anything."
    rm "$KEEP_LIST"
    exit 1
fi

# Удаляем только те файлы, которых нет в KEEP_LIST
cd "$CACHE_DIR"
deleted_count=0
for f in *_*.tar.zst; do
    [[ -e "$f" ]] || continue
    
    if ! grep -qxF "$f" "$KEEP_LIST"; then
        log_info "Deleting orphaned cache: $f"
        rm -f "$f"
        # Также удаляем старый симлинк, если он есть и ведет на этот файл
        STAGENAME_BASE="${f%_*}"
        [[ -L "${STAGENAME_BASE}.tar.zst" ]] && rm "${STAGENAME_BASE}.tar.zst"
        ((deleted_count++))
    fi
done

log_info "Cleanup finished. Removed $deleted_count orphaned files."
rm "$KEEP_LIST"
