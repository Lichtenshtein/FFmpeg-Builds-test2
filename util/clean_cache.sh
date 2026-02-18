#!/bin/bash

set -e
shopt -s globstar  # Гарантируем поддержку вложенных папок

# Подгружаем переменные, чтобы знать TARGET/VARIANT
TARGET="${1:-$TARGET}"
VARIANT="${2:-$VARIANT}"
source "$(dirname "$0")/vars.sh" "$TARGET" "$VARIANT" > /dev/null 2>&1 || true

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
    if ( export TARGET="$TARGET" VARIANT="$VARIANT"; source "$STAGE" >/dev/null 2>&1 && ffbuild_enabled ); then
        
        # Генерируем команду загрузки (с явным пробросом контекста) точно так же, как в download.sh
        DL_COMMAND=$(export TARGET="$TARGET" VARIANT="$VARIANT"; \
        bash -c "source util/vars.sh \"$TARGET\" \"$VARIANT\" &>/dev/null; \
                      source util/dl_functions.sh; \
                      source \"$STAGE\"; \
                      ffbuild_enabled && ffbuild_dockerdl" 2>/dev/null || echo "")

        if [[ -n "$DL_COMMANDS" ]]; then
            # Синхронизируем фильтры с download.sh
            DL_COMMANDS="${DL_COMMANDS//retry-tool /}"
            DL_COMMANDS="${DL_COMMANDS//git fetch --unshallow/true}"
            # Пакет с загрузкой: вычисляем хеш
            SCRIPT_CODE=$(grep -v '^[[:space:]]*#' "$STAGE" | grep -v '^[[:space:]]*$')
            DL_HASH=$( (echo "$DL_COMMAND"; echo "$SCRIPT_CODE") | sha256sum | cut -d" " -f1 | cut -c1-16)
            CURRENT_FILE="${STAGENAME}_${DL_HASH}.tar.zst"
            # Добавляем в список текущий файл и симлинк
            log_debug "Protecting hash: ${STAGENAME}_${DL_HASH}.tar.zst"
            echo "$CURRENT_FILE" >> "$RAW_KEEP_LIST"
            # Также защищаем символическую ссылку, если она есть
            echo "${STAGENAME}.tar.zst" >> "$RAW_KEEP_LIST"
            log_debug "Protecting current version: $CURRENT_FILE"
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

# Читаем список файлов в массив для скорости
mapfile -t FILES_IN_CACHE < <(ls *.tar.zst 2>/dev/null)

for f in "${FILES_IN_CACHE[@]}"; do
    [[ -e "$f" ]] || continue

    # Проверяем, есть ли файл в нашем списке разрешенных
    # Использование 'comm' или 'grep -Fq' на отсортированном списке очень быстрое
    if ! grep -qxF "$f" "$FINAL_KEEP_LIST"; then
        
        # удаляем только если файл не слишком свежий (запас 15 мин)
        # Это защищает файлы, которые качаются ПРЯМО СЕЙЧАС в параллельном процессе
        if [[ -z $(find "$f" -mmin -15 2>/dev/null) ]]; then
            log_info "Deleting orphaned/old cache: $f"
            rm -f "$f"
            
            # Если это был файл, на который указывал битый симлинк удаляем и симлинк
            BASE="${f%%_*}"
            if [[ -L "${BASE}.tar.zst" && ! -e "${BASE}.tar.zst" ]]; then
                rm "${BASE}.tar.zst"
            fi
            
            ((deleted_count++))
        fi
    fi
done

rm -f "$FINAL_KEEP_LIST"
log_info "Cleanup finished. Removed $deleted_count orphaned files."