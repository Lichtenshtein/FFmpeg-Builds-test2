#!/bin/bash

set -e
shopt -s globstar  # Гарантируем поддержку вложенных папок

# Подгружаем переменные, чтобы знать TARGET/VARIANT
# Очищаем входные аргументы от возможных флагов lto/skip
# Берем только первое и второе слово
CLEAN_TARGET=$(echo "${1:-$TARGET}" | awk '{print $1}')
CLEAN_VARIANT=$(echo "${2:-$VARIANT}" | awk '{print $1}')

source "$(dirname "$0")/vars.sh" "$CLEAN_TARGET" "$CLEAN_VARIANT" > /dev/null 2>&1 || true

CACHE_DIR="$(dirname "$0")/../.cache/downloads"
SCRIPTS_DIR="$(dirname "$0")/../scripts.d"

if [[ ! -d "$CACHE_DIR" ]]; then
    log_warn "Cache directory $CACHE_DIR not found. Nothing to clean."
    exit 0
fi

log_info "Starting smart cleanup in $CACHE_DIR..."

# Собираем список всех актуальных хешей для активных скриптов
# Временный файл для накопления имен
RAW_KEEP_LIST=$(mktemp)

for STAGE in "$SCRIPTS_DIR"/**/*.sh; do
    [[ -f "$STAGE" ]] || continue
    STAGENAME="$(basename "$STAGE" .sh)"

    # Проверяем, включен ли компонент
    if ( export TARGET="$CLEAN_TARGET" VARIANT="$CLEAN_VARIANT"; source "$STAGE" >/dev/null 2>&1 && ffbuild_enabled ); then

        DL_HASH=$(get_stage_hash "$STAGE")

        if [[ -n "$DL_HASH" ]]; then
            CURRENT_FILE="${STAGENAME}_${DL_HASH}.tar.zst"
            # Добавляем в список текущий файл и симлинк
            log_debug "Protecting hash: ${STAGENAME}_${DL_HASH}.tar.zst"
            echo "$CURRENT_FILE" >> "$RAW_KEEP_LIST"
            # Также защищаем символическую ссылку, если она есть
            log_debug "Protecting current version: $CURRENT_FILE"
            echo "${STAGENAME}.tar.zst" >> "$RAW_KEEP_LIST"
        fi
    fi
done

# Сортируем и удаляем дубликаты один раз
FINAL_KEEP_LIST=$(mktemp)
sort -u "$RAW_KEEP_LIST" > "$FINAL_KEEP_LIST"
rm -f "$RAW_KEEP_LIST"
# Удаляем только те файлы, которых нет в KEEP_LIST
cd "$CACHE_DIR" || exit 0
log_info "Cleaning up orphaned and outdated cache files..."
deleted_count=0

# Используем глоб напрямую, чтобы избежать проблем с пустыми переменными
for f in *.tar.zst; do
    [[ -f "$f" ]] || continue
    [[ -L "$f" ]] && continue # Пропускаем симлинки, их проверим отдельно

    # Если файла нет в списке актуальных
    if ! grep -qxF "$f" "$FINAL_KEEP_LIST"; then
        # Удаляем только если файл старше 15 минут (защита от параллельных процессов)
        if [[ -z $(find "$f" -mmin -15 2>/dev/null) ]]; then
            log_info "Deleting orphaned/old cache: $f"
            rm -f "$f" || true
            # Безопасный инкремент (не роняет скрипт при set -e)
            deleted_count=$((deleted_count + 1))
        fi
    fi
done

# Дополнительная чистка битых симлинков
for l in *.tar.zst; do
    if [[ -L "$l" && ! -e "$l" ]]; then
        log_debug "Removing broken symlink: $l"
        rm -f "$l"
    fi
done

rm -f "$FINAL_KEEP_LIST"
log_info "Cleanup finished. Removed $deleted_count orphaned files."
exit 0
