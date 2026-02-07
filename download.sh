#!/bin/bash
set -e
cd "$(dirname "$0")"
source util/vars.sh dl only

# Создаем папку для кэша
mkdir -p .cache/downloads
DL_DIR="$PWD/.cache/downloads"

# Функция для имитации ffbuild_dockerdl локально
# (Подразумевается, что на раннере есть git, curl, wget)
source util/dl_functions.sh

echo "Downloading sources for all enabled stages..."

for STAGE in scripts.d/*.sh scripts.d/*/*.sh; do
    (
        source "$STAGE"
        STAGENAME="$(basename "$STAGE" | sed 's/.sh$//')"
        
        # Проверяем, включен ли этап для текущей цели
        if ! ffbuild_enabled; then continue; fi
        
        DL_COMMAND="$(ffbuild_dockerdl)"
        if [[ -z "$DL_COMMAND" ]]; then continue; fi
        
        # Вычисляем хэш команды загрузки для проверки актуальности
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
        cd "$WORK_DIR"
        
        # Выполняем команду загрузки
        eval "$DL_COMMAND"
        
        # Архивируем результат
        tar -cpJf "$TGT_FILE" .
        ln -sf "${STAGENAME}_${DL_HASH}.tar.xz" "$LATEST_LINK"
        
        rm -rf "$WORK_DIR"
    )
done

# Очистка старых версий кэша
./util/clean_cache.sh
