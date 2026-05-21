#!/bin/bash
source "$(dirname "${BASH_SOURCE}")"/windows-install-static.sh
source "$(dirname "${BASH_SOURCE}")"/defaults-gpl.sh

# Сохраняем предыдущую версию функции, если она была (например из windows-install-static)
eval "prev_ffbuild_configure_gpl() { $(declare -f ffbuild_configure | sed '1,2d;$d'); }"

ffbuild_configure() {
    # Вызываем "родителя"
    prev_ffbuild_configure_gpl 2>/dev/null || true
    # Добавляем свои флаги
    echo "--pkg-config-flags=\"--static --libs-only-l\" --disable-shared --enable-static --enable-gpl --enable-version3"
}
