#!/bin/bash

source "$(dirname "${BASH_SOURCE}")"/win64-gpl.sh

# Бэкапим функцию из GPL скрипта
eval "prev_ffbuild_configure_nonfree() { $(declare -f ffbuild_configure | sed '1,2d;$d'); }"

ffbuild_configure() {
    # Сначала печатаем всё, что было в GPL (и выше)
    prev_ffbuild_configure_nonfree 2>/dev/null || true
    # Добавляем nonfree
    echo "--enable-nonfree"
}
LICENSE_FILE=""