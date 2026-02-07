#!/bin/bash
set -e
cd "$(dirname "$0")"
source util/vars.sh dl only
source util/dl_functions.sh

mkdir -p .cache/downloads
DL_DIR="$PWD/.cache/downloads"

echo "Downloading sources..."

# Массив всех скриптов (рекурсивно)
mapfile -t STAGES < <(find scripts.d -name "*.sh")

for STAGE in "${STAGES[@]}"; do
    # Пропускаем, если файл не существует
    [[ -f "$STAGE" ]] || continue
    
    # Сбрасываем переменные перед загрузкой нового скрипта
    unset SCRIPT_REPO SCRIPT_COMMIT
    
    # Загружаем скрипт этапа в subshell, чтобы не загрязнять окружение, 
    # но результат (команду) выводим наружу
    STAGENAME="$(basename "$STAGE" | sed 's/.sh$//')"
    
    # Проверяем, включен ли этап (выполняем в subshell)
    if ! ( source "$STAGE" && ffbuild_enabled ); then
        continue
    fi
    
    # Получаем команду загрузки
    DL_COMMAND=$( ( source "$STAGE" && ffbuild_dockerdl "." ) )
    
    if [[ -z "$DL_COMMAND" ]]; then
        continue
    fi
    
    # Очистка команды от специфичных префиксов
    DL_COMMAND="${DL_COMMAND//retry-tool /}"
    
    DL_HASH="$(echo "$DL_COMMAND" | sha256sum | cut -d" " -f1)"
    TGT_FILE="${DL_DIR}/${STAGENAME}_${DL_HASH}.tar.xz"
    LATEST_LINK="${DL_DIR}/${STAGENAME}.tar.xz"

    if [[ -f "$TGT_FILE" ]]; then
        echo "Cache hit for $STAGENAME"
        ln -sf "${STAGENAME}_${DL_HASH}.tar.xz" "$LATEST_LINK"
        continue
    fi

    echo "Downloading $STAGENAME..."
    WORK_DIR=$(mktemp -d)
    
    # Выполняем загрузку в изолированном окружении
    # Используем bash -c для стабильного eval внутри временной папки
    if ( cd "$WORK_DIR" && bash -c "$DL_COMMAND" ); then
        tar -cpJf "$TGT_FILE" -C "$WORK_DIR" .
        ln -sf "${STAGENAME}_${DL_HASH}.tar.xz" "$LATEST_LINK"
    else
        echo "Failed to download $STAGENAME. Command was: $DL_COMMAND"
        rm -rf "$WORK_DIR"
        exit 1
    fi
    
    rm -rf "$WORK_DIR"
done

echo "All downloads finished successfully."
