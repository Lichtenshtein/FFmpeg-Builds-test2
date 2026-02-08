#!/bin/bash
set -eo pipefail

# Переходим в корень репозитория (на один уровень выше папки util)
cd "$(dirname "$0")/.."

find scripts.d variants addins -type f -name "*.sh" -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d" " -f1
