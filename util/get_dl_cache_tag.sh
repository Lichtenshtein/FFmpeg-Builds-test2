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
find scripts.d variants addins -type f -name "*.sh" -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d" " -f1
