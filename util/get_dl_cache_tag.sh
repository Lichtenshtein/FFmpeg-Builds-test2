#!/bin/bash
set -eo pipefail
cd "$(dirname "$0")/.."

# Очищаем временный файл перед началом
echo -n "" > cache_state.tmp

# Добавляем TARGET и VARIANT в состояние кэша.
# Используем >>, чтобы не затереть предыдущую запись.
echo "$TARGET-$VARIANT" >> cache_state.tmp

# Хешируем все скрипты и утилиты.
# Добавлена папка patches, так как изменение патча должно инвалидировать кэш.
# Используем -type f, чтобы не хешировать директории.
find scripts.d util variants patches -type f -name "*.sh" -o -name "*.patch" -print0 | sort -z | xargs -0 sha256sum >> cache_state.tmp

# Добавляем основной скрипт загрузки
if [[ -f "download.sh" ]]; then
    sha256sum download.sh >> cache_state.tmp
fi

# Генерируем финальный хеш и выводим его (этот вывод перехватывает GitHub Actions)
sha256sum cache_state.tmp | cut -d" " -f1

# Удаляем временный файл
rm cache_state.tmp
