#!/bin/bash

set -e

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
# Мы создадим временный список имен файлов, которые НУЖНО оставить.
KEEP_LIST=$(mktemp)

for STAGE in "$SCRIPTS_DIR"/**/*.sh; do
    [[ -e "$STAGE" ]] || continue
    STAGENAME="$(basename "$STAGE" | sed 's/.sh$//')"

    # Проверяем, включен ли скрипт для текущего таргета
    # Экспортируем переменные явно для подпроцесса
    if ( export TARGET="$TARGET" VARIANT="$VARIANT"; source "$STAGE" >/dev/null 2>&1 && ffbuild_enabled ); then
        
        # Получаем команду загрузки (с явным пробросом контекста)
        DL_COMMAND=$(export TARGET="$TARGET" VARIANT="$VARIANT"; bash -c "source util/vars.sh \$TARGET \$VARIANT &>/dev/null; source util/dl_functions.sh; source '$STAGE'; ffbuild_dockerdl" 2>/dev/null || echo "")

        if [[ -n "$DL_COMMAND" ]]; then
            # Пакет с загрузкой: вычисляем хеш
            SCRIPT_CODE=$(grep -v '^[[:space:]]*#' "$STAGE" | grep -v '^[[:space:]]*$')
            DL_HASH=$( (echo "$DL_COMMAND"; echo "$SCRIPT_CODE") | sha256sum | cut -d" " -f1 | cut -c1-16)
            echo "${STAGENAME}_${DL_HASH}.tar.zst" >> "$KEEP_LIST"
            log_debug "Protecting hash: ${STAGENAME}_${DL_HASH}.tar.zst"
        fi

        # РЕЗЕРВНАЯ ЗАЩИТА (Белый список по имени)
        # Защищаем любой файл, который начинается на имя активного скрипта.
        # Это предотвратит удаление, если расчет хеша выше дал сбой.
        ls "$CACHE_DIR"/${STAGENAME}_*.tar.zst 2>/dev/null | xargs -n1 basename 2>/dev/null >> "$KEEP_LIST" || true
        # Защищаем базовый симлинк
        echo "${STAGENAME}.tar.zst" >> "$KEEP_LIST"
    fi
done

# Удаляем только те файлы, которых нет в KEEP_LIST
cd "$CACHE_DIR" || exit 0
log_info "Cleaning up orphaned cache files..."
deleted_count=0

# Отключаем set -e для цикла удаления
set +e
mapfile -t ALL_FILES < <(ls *_*.tar.zst 2>/dev/null)

for f in "${ALL_FILES[@]}"; do
    [[ -f "$f" ]] || continue

    # Защита новых файлов (15 минут вместо 5, для надежности в GHA)
    if [[ -n $(find "$f" -mmin -15 2>/dev/null) ]]; then
        continue
    fi

    # Если файла НЕТ в списке защиты — удаляем
    if ! grep -qxF "$f" "$KEEP_LIST" 2>/dev/null; then
        log_info "Deleting orphaned cache: $f"
        rm -f "$f"
        
        # Чистим соответствующий симлинк, если он ведет "в никуда"
        BASE="${f%%_*}"
        if [[ -L "${BASE}.tar.zst" && "$(readlink "${BASE}.tar.zst")" == "$f" ]]; then
            rm "${BASE}.tar.zst"
        fi
        ((deleted_count++))
    fi
done

set -e
rm -f "$KEEP_LIST"
log_info "Cleanup finished successfully. Removed $deleted_count files."
exit 0