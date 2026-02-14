#!/bin/bash
set -eo pipefail

# Переходим в корень проекта (на уровень выше util)
cd "$(dirname "$0")/.."

# Проверяем, что папки существуют, прежде чем запускать find
# if [ ! -d "scripts.d" ]; then
    # echo "ERROR: scripts.d not found at $(pwd)" >&2
    # exit 1
# fi

# будем хэшировать только те строки, которые начинаются с SCRIPT_ или ffbuild_dockerdl. Это те части кода, которые определяют, что скачивать
# Извлекаем только значимые для загрузки строки:
# Переменные SCRIPT_...
# Тело функции ffbuild_dockerdl (если она переопределена)
# Это игнорирует комментарии, пробелы и логику компиляции (ffbuild_dockerbuild)
# Теперь можно менять CFLAGS, добавлять комментарии или исправлять ошибки в ffbuild_dockerbuild ключ кэша GitHub не изменится, и папка .cache/downloads восстановится мгновенно
# Если вы изменить SCRIPT_COMMIT="v1.2.3" на v1.2.4, хэш изменится, и GitHub создаст новую запись в кэше.

find scripts.d variants addins -type f -name "*.sh" -print0 | sort -z | xargs -0 \
    grep -E "^(SCRIPT_|ffbuild_dockerdl)" | sha256sum | cut -d" " -f1

# Старая логика
# Если изменяется хотя бы один символ в любом .sh файле в scripts.d, GitHub Actions сочтет кэш невалидным и начнет скачивать всё заново (если не найдет restore-keys). Однако workflow.yaml использует restore-keys: dl-cache-, что спасает ситуацию.

# find scripts.d variants addins -type f -name "*.sh" -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d" " -f1