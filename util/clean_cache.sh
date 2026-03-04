#!/bin/bash

set -e
shopt -s globstar  # Гарантируем поддержку вложенных папок

# Подгружаем переменные, чтобы знать TARGET/VARIANT
# Очищаем входные аргументы от возможных флагов lto/skip
# Берем только первое и второе слово
CLEAN_TARGET=$(echo "${1:-$TARGET}" | awk '{print $1}')
CLEAN_VARIANT=$(echo "${2:-$VARIANT}" | awk '{print $1}')

# если таргет или вариант не определены, выходим.
# Без этого vars.sh может вернуть ошибку или инициализироваться неверно, 
# что приведет к удалению ВСЕГО кеша (так как список PROTECTED будет пустым).
if [[ -z "$CLEAN_TARGET" || -z "$CLEAN_VARIANT" ]]; then
    log_error "${CROSS_MARK} ERROR: Cleanup aborted. TARGET and VARIANT must be specified."
    log_debug "Usage: ./clean_cache.sh <target> <variant>"
    exit 1
fi

# передаем аргументы явно, чтобы vars.sh не пытался читать их из контекста
if ! source "$(dirname "$0")/vars.sh" "$CLEAN_TARGET" "$CLEAN_VARIANT" > /dev/null 2>&1; then
    log_error "${CROSS_MARK} ERROR: Failed to source vars.sh for $CLEAN_TARGET-$CLEAN_VARIANT"
    exit 1
fi

CACHE_DIR="$(dirname "$0")/../.cache/downloads"
SCRIPTS_DIR="$(dirname "$0")/../scripts.d"

if [[ ! -d "$CACHE_DIR" ]]; then
    log_warn "${XCLAM_MARK} Cache directory $CACHE_DIR not found. Nothing to clean."
    exit 0
fi

log_info "${BROOM_MARK} Starting smart cleanup in $CACHE_DIR..."

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
            log_debug "${LOCK_MARK} Protecting hash: ${STAGENAME}_${DL_HASH}.tar.zst"
            echo "$CURRENT_FILE" >> "$RAW_KEEP_LIST"
            # Также защищаем символическую ссылку, если она есть
            log_debug "${LOCK_MARK} Protecting current version: $CURRENT_FILE"
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
log_info "${BROOM_MARK} Cleaning up orphaned and outdated cache files..."
deleted_count=0

# Используем глоб напрямую, чтобы избежать проблем с пустыми переменными
for f in *.tar.zst; do
    [[ -f "$f" ]] || continue
    [[ -L "$f" ]] && continue # Пропускаем симлинки, их проверим отдельно

    # Если файла нет в списке актуальных
    if ! grep -qxF "$f" "$FINAL_KEEP_LIST"; then
        # Удаляем только если файл старше 60 минут (защита от параллельных процессов)
        if [[ -z $(find "$f" -mmin -60 2>/dev/null) ]]; then
            log_info "${BROOM_MARK} Deleting orphaned/old cache: $f"
            rm -f "$f" || true
            # Безопасный инкремент (не роняет скрипт при set -e)
            deleted_count=$((deleted_count + 1))
        fi
    fi
done

# Дополнительная чистка битых симлинков
for l in *.tar.zst; do
    if [[ -L "$l" && ! -e "$l" ]]; then
        log_debug "${BROOM_MARK} Removing broken symlink: $l"
        rm -f "$l"
    fi
done

rm -f "$FINAL_KEEP_LIST"
log_info "${CHECK_MARK} Cleanup finished. Removed $deleted_count orphaned files."
exit 0
