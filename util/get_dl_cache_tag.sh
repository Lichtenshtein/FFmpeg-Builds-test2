#!/bin/bash
set -eo pipefail

# Переходим в корень проекта (на уровень выше util)
cd "$(dirname "$0")/.."

# Проверяем, что папки существуют, прежде чем запускать find
if [ ! -d "scripts.d" ]; then
    echo "ERROR: scripts.d not found at $(pwd)" >&2
    exit 1
fi

# Генерируем хэш
# Если изменяется хотя бы один символ в любом .sh файле в scripts.d, GitHub Actions сочтет кэш невалидным и начнет скачивать всё заново (если не найдет restore-keys). Однако workflow.yaml использует restore-keys: dl-cache-, что спасает ситуацию.
find scripts.d variants addins -type f -name "*.sh" -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d" " -f1
