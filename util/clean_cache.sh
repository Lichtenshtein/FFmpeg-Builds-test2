#!/bin/bash

set -e
shopt -s globstar  # Гарантируем поддержку вложенных папок
# shopt -s nullglob

# Подгружаем переменные, чтобы знать TARGET/VARIANT
# Очищаем входные аргументы от возможных флагов lto/skip
# Берем только первое и второе слово
CLEAN_TARGET=$(echo "${1:-$TARGET}" | awk '{print $1}')
CLEAN_VARIANT=$(echo "${2:-$VARIANT}" | awk '{print $1}')

# если таргет или вариант не определены, выходим.
# Без этого vars.sh может вернуть ошибку или инициализироваться неверно, 
# что приведет к удалению ВСЕГО кеша (так как список PROTECTED будет пустым).
if [[ -z "$CLEAN_TARGET" || -z "$CLEAN_VARIANT" ]]; then
    echo "ERROR: Cleanup aborted. TARGET and VARIANT must be specified." >&2
    echo "Usage: ./clean_cache.sh <target> <variant>" >&2
    exit 1
fi

# передаем аргументы явно, чтобы vars.sh не пытался читать их из контекста
if ! source "$(dirname "$0")/vars.sh" "$CLEAN_TARGET" "$CLEAN_VARIANT" 2>/dev/null; then
    echo "ERROR: Failed to source vars.sh for $CLEAN_TARGET-$CLEAN_VARIANT" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/../.cache/downloads"
SCRIPTS_DIR="$SCRIPT_DIR/../scripts.d"

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

    # Если мы собираем только часть стадий, 
    # не нужно защищать кэш для тех, что не входят в список.
    if [[ -n "$ONLY_STAGE" ]]; then
        # if ! echo "$STAGENAME" | grep -qE "$ONLY_STAGE"; then
        if [[ ! "$STAGENAME" =~ $ONLY_STAGE ]]; then
            log_debug "Skipping $STAGENAME: does not match ONLY_STAGE filter."
            continue
        fi
    fi

    # Проверяем, включен ли компонент
    if ( set +e; source "$(dirname "$0")/vars.sh" "$CLEAN_TARGET" "$CLEAN_VARIANT" > /dev/null 2>&1 \
     && source "$STAGE" > /dev/null 2>&1 \
     && ffbuild_enabled ); then

        DL_HASH=$(get_stage_hash "$STAGE")

        if [[ -n "$DL_HASH" ]]; then
            CURRENT_FILE="${STAGENAME}_${DL_HASH}.tar.zst"
            # Добавляем в список текущий файл и симлинк
            log_debug "${LOCK_MARK} Protecting: $CURRENT_FILE and ${STAGENAME}.tar.zst (symlink)"
            echo "$CURRENT_FILE" >> "$RAW_KEEP_LIST"
            # Также защищаем символическую ссылку, если она есть
            echo "${STAGENAME}.tar.zst" >> "$RAW_KEEP_LIST"
        fi
    fi
done

# Сортируем и удаляем дубликаты один раз
FINAL_KEEP_LIST=$(mktemp)
trap 'rm -f "$RAW_KEEP_LIST" "$FINAL_KEEP_LIST"' EXIT
sort -u "$RAW_KEEP_LIST" > "$FINAL_KEEP_LIST"
rm -f "$RAW_KEEP_LIST"
# Удаляем только те файлы, которых нет в KEEP_LIST
cd "$CACHE_DIR" || exit 0
log_info "${BROOM_MARK} Cleaning up orphaned and outdated cache files and symlinks..."
deleted_count=0

# Гарантируем, что в списке нет лишних пробелов и символов возврата каретки
sed -i 's/\r//g; s/[[:space:]]*$//' "$FINAL_KEEP_LIST"
# Читаем актуальный список в массив
mapfile -t PROTECTED_FILES < "$FINAL_KEEP_LIST"

# Выводим отладку
log_debug "FINAL_KEEP_LIST contents (first 10):"
head -n 10 "$FINAL_KEEP_LIST" || true

# Используем глоб напрямую, чтобы избежать проблем с пустыми переменными
for f in *.tar.zst; do
    [[ -e "$f" || -L "$f" ]] || continue # Проверяем существование или наличие ссылки

    # Проверяем, есть ли файл в массиве "защищенных"
    is_protected=false
    for p in "${PROTECTED_FILES[@]}"; do
        [[ "$f" == "$p" ]] && is_protected=true && break
    done

    # Если объекта (файла или симлинка) нет в списке актуальных
    if [[ "$is_protected" == "false" ]]; then
        if [[ -L "$f" ]]; then
            log_info "${BROOM_MARK} Removing obsolete symlink: $f"
            rm -f "$f"
            ((deleted_count++))
        elif [[ -f "$f" ]]; then
            # Стандартная защита 30 мин для тяжелых архивов
            if [[ -n $(find "$f" -mmin +30 2>/dev/null) ]]; then
                log_info "${BROOM_MARK} Deleting orphaned cache file: $f"
                rm -f "$f"
                ((deleted_count++))
            fi
        fi
    fi
done

# Дополнительная страховка: удаляем реально БИТЫЕ ссылки, 
# которые могли остаться из-за ошибок ручного удаления файлов
find . -maxdepth 1 -xtype l -delete || true

log_info "${CHECK_MARK} Cleanup finished. Removed $deleted_count outdated/orphaned cache files."
exit 0
