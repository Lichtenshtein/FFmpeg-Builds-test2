#!/bin/bash

# set -xe
# cd "$(dirname "$0")"/../.cache/downloads
# find . $(printf "! -name %s " $(find . -type l -exec basename -a {} + -exec readlink {} +)) -delete

set -e
cd .cache/downloads || exit 0
# Удаляем только те файлы .tar.xz, на которые НЕТ симлинков в этой же папке
find . -name "*.tar.xz" -type f -not -name "*_*" -links 1 -delete
