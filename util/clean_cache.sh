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
    
    # Получаем команду загрузки
    DL_COMMAND=$(bash -c "source util/vars.sh \"$TARGET\" \"$VARIANT\" &>/dev/null; \
                          source util/dl_functions.sh; \
                          source \"$STAGE\"; \
                          ffbuild_enabled && ffbuild_dockerdl" || echo "")

    if [[ -z "$DL_COMMAND" ]]; then
        # Это мета-пакет. Защищаем ВСЕ файлы, начинающиеся на его имя,
        # чтобы случайно не удалить локальные аддоны или базовый тулчейн.
        log_debug "Protecting meta-package: $STAGENAME"
        echo "${STAGENAME}.tar.zst" >> "$KEEP_LIST"
        # Защищаем все существующие хешированные версии этого стейджа
        ls "$CACHE_DIR"/${STAGENAME}_*.tar.zst 2>/dev/null | xargs -n1 basename 2>/dev/null >> "$KEEP_LIST" || true
    else
        # Это обычный пакет с загрузкой из сети. Вычисляем текущий валидный хеш.
        SCRIPT_CODE=$(grep -v '^[[:space:]]*#' "$STAGE" | grep -v '^[[:space:]]*$')
        DL_HASH=$( (echo "$DL_COMMAND"; echo "$SCRIPT_CODE") | sha256sum | cut -d" " -f1 | cut -c1-16)
        
        VALID_FILE="${STAGENAME}_${DL_HASH}.tar.zst"
        echo "$VALID_FILE" >> "$KEEP_LIST"
        log_debug "Protecting active source: $VALID_FILE"
    fi
done

# Проверка на "пустой список" (защита от случайной очистки всего кэша)
if [[ ! -s "$KEEP_LIST" ]]; then
    log_error "Safety trigger: No active source files identified. Refusing to delete anything."
    rm "$KEEP_LIST"
    exit 1
fi

# Удаляем только те файлы, которых нет в KEEP_LIST
cd "$CACHE_DIR" || exit 0
deleted_count=0

# Читаем все файлы в массив, чтобы избежать проблем с Broken Pipe
mapfile -t FILES < <(ls *_*.tar.zst 2>/dev/null)

for f in *_*.tar.zst; do
    [[ -e "$f" ]] || continue

    # Проверка на свежесть (5 минут)
    if [[ -n $(find "$f" -mmin -5 2>/dev/null) ]]; then
        log_debug "Skipping recently created file: $f"
        continue
    fi

    if ! grep -qxF "$f" "$KEEP_LIST"; then
        log_info "Deleting orphaned cache: $f"
        rm -f "$f" || true
        # Также удаляем старый симлинк, если он есть и ведет на этот файл
        STAGENAME_BASE="${f%_*}"
        [[ -L "${STAGENAME_BASE}.tar.zst" ]] && rm "${STAGENAME_BASE}.tar.zst"
        ((deleted_count++))
    fi
done

log_info "Cleanup finished. Removed $deleted_count orphaned files."
rm "$KEEP_LIST"
exit 0
