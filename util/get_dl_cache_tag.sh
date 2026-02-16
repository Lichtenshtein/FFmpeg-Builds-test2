#!/bin/bash
set -eo pipefail
cd "$(dirname "$0")/.."

# Если изменить VARIANT с gpl на nonfree, хэш останется прежним. GitHub Actions восстановит старый кэш, где лежат исходники только для gpl, и сборка упадет.
echo "$TARGET-$VARIANT" >> cache_state.tmp

# Хешируем: 
# Все скрипты сборки
# Все файлы в util/ (включая vars.sh и dl_functions.sh)
# Сам download.sh
find scripts.d util variants -type f -name "*.sh" -print0 | sort -z | xargs -0 sha256sum > cache_state.tmp
sha256sum download.sh >> cache_state.tmp

sha256sum cache_state.tmp | cut -d" " -f1
rm cache_state.tmp
