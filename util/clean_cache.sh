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
cd "$CACHE_DIR" || { log_warn "Cannot cd to cache"; exit 0; }
log_info "Cleaning up orphaned cache files..."
deleted_count=0

# Читаем все файлы в массив, чтобы избежать проблем с Broken Pipe
mapfile -t ALL_FILES < <(ls *_*.tar.zst 2>/dev/null)

# Если файлов нет - выходим
if [[ ${#ALL_FILES[@]} -eq 0 ]]; then
    log_info "No cache files to clean."
    rm "$KEEP_LIST"
    exit 0
fi

for f in "${ALL_FILES[@]}"; do
    [[ -f "$f" ]] || continue

    # Защита "свежих" файлов (5 минут). 
    # В GHA find может вернуть ошибку, если файл исчез, поэтому || true
    IS_NEW=$(find "$f" -mmin -5 2>/dev/null || echo "")
    if [[ -n "$IS_NEW" ]]; then
        log_debug "Skipping new file: $f"
        continue
    fi

    # Проверка по списку (используем grep внутри if, это безопасно для set -e)
    if ! grep -qxF "$f" "$KEEP_LIST"; then
        log_info "Deleting orphaned cache: $f"
        
        # Удаляем файл
        rm -f "$f" || true
        
        # Удаляем симлинк, если он вел на этот файл (STAGENAME.tar.zst)
        # Получаем базу имени (все до первого нижнего подчеркивания)
        STAGENAME_BASE="${f%%_*}"
        if [[ -L "${STAGENAME_BASE}.tar.zst" ]]; then
            # Проверяем, куда ведет симлинк. Если на удаленный файл - стираем его.
            TARGET_LINK=$(readlink "${STAGENAME_BASE}.tar.zst")
            if [[ "$TARGET_LINK" == "$f" ]]; then
                rm "${STAGENAME_BASE}.tar.zst" || true
            fi
        fi
        ((deleted_count++))
    fi
done

rm -f "$KEEP_LIST" || true
log_info "Cleanup finished successfully."
exit 0