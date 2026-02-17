#!/bin/bash

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
    
    # Пытаемся вычислить хеш (как в download.sh)
    # Добавляем экспорт переменных прямо в вызов для надежности
    DL_COMMAND=$(bash -c "export TARGET='$TARGET'; export VARIANT='$VARIANT'; source util/vars.sh \$TARGET \$VARIANT &>/dev/null; source util/dl_functions.sh; source '$STAGE'; ffbuild_enabled && ffbuild_dockerdl" 2>/dev/null || echo "")

    # Проверяем, включен ли скрипт вообще
    # Если скрипт включен, мы ОБЯЗАНЫ защитить его файлы
    if ( export TARGET="$TARGET"; export VARIANT="$VARIANT"; source "$STAGE" >/dev/null 2>&1 && ffbuild_enabled ); then
        
        if [[ -n "$DL_COMMAND" ]]; then
            # Вариант 1: Пакет с загрузкой. Считаем хеш и защищаем конкретный файл.
            SCRIPT_CODE=$(grep -v '^[[:space:]]*#' "$STAGE" | grep -v '^[[:space:]]*$')
            DL_HASH=$( (echo "$DL_COMMAND"; echo "$SCRIPT_CODE") | sha256sum | cut -d" " -f1 | cut -c1-16)
            echo "${STAGENAME}_${DL_HASH}.tar.zst" >> "$KEEP_LIST"
            log_debug "Protecting by hash: ${STAGENAME}_${DL_HASH}.tar.zst"
        fi

        # Резервная защита (Мета-пакеты и "свежак"). 
        # Защищаем все файлы, которые начинаются на STAGENAME_
        # Это спасет от удаления, если расчет хеша выше сорвался.
        ls "$CACHE_DIR"/${STAGENAME}_*.tar.zst 2>/dev/null | xargs -n1 basename 2>/dev/null >> "$KEEP_LIST" || true
        # Защищаем базовый симлинк
        echo "${STAGENAME}.tar.zst" >> "$KEEP_LIST"
    fi
done

# Проверка на пустой список (безопасность)
if [[ ! -s "$KEEP_LIST" ]]; then
    log_error "Safety trigger: KEEP_LIST is empty. Refusing to delete."
    rm -f "$KEEP_LIST"
    exit 1
fi

# Удаляем только те файлы, которых нет в KEEP_LIST
cd "$CACHE_DIR" || { log_warn "Cannot cd to cache"; exit 0; }
log_info "Cleaning up orphaned cache files..."
deleted_count=0

# Отключаем set -e только на время цикла очистки, чтобы избежать случайных вылетов
set +e
# Читаем все файлы в массив, чтобы избежать проблем с Broken Pipe
mapfile -t ALL_FILES < <(ls *_*.tar.zst 2>/dev/null)

for f in "${ALL_FILES[@]}"; do
    [[ -f "$f" ]] || continue

    # Защита "свежих" файлов (5 минут). 
    # В GHA find может вернуть ошибку, если файл исчез, поэтому || true
    IS_NEW=$(find "$f" -mmin -5 2>/dev/null || echo "")
    if [[ -n "$IS_NEW" ]]; then
        log_debug "Skipping new file: $f"
        continue
    fi

    # Сверяем со списком защиты
    if ! grep -qxF "$f" "$KEEP_LIST"; then
        log_info "Deleting orphaned cache: $f"
        rm -f "$f" || true
        
        # Чистим битые симлинки
        STAGENAME_BASE="${f%%_*}"
        if [[ -L "${STAGENAME_BASE}.tar.zst" ]]; then
            if [[ "$(readlink "${STAGENAME_BASE}.tar.zst")" == "$f" ]]; then
                rm "${STAGENAME_BASE}.tar.zst" || true
            fi
        fi
        ((deleted_count++))
    fi
done

set -e
rm -f "$KEEP_LIST"
log_info "Cleanup finished successfully. Removed $deleted_count files."
exit 0