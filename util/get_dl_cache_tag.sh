#!/bin/bash
set -eo pipefail
cd "$(dirname "$0")/.."

# Хешируем: 
# Все скрипты сборки
# Все файлы в util/ (включая vars.sh и dl_functions.sh)
# Сам download.sh
find scripts.d util variants -type f -name "*.sh" -print0 | sort -z | xargs -0 sha256sum > cache_state.tmp
sha256sum download.sh >> cache_state.tmp

sha256sum cache_state.tmp | cut -d" " -f1
rm cache_state.tmp
