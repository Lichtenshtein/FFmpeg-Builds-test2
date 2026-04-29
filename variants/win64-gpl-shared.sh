#!/bin/bash
source "$(dirname "${BASH_SOURCE}")"/windows-install-shared.sh
source "$(dirname "${BASH_SOURCE}")"/defaults-gpl.sh

eval "prev_ffbuild_configure_gpl() { $(declare -f ffbuild_configure | sed '1,2d;$d'); }"

ffbuild_configure() {
    prev_ffbuild_configure_gpl 2>/dev/null || true
    echo "--pkg-config-flags=\"\" --enable-shared --disable-static --enable-gpl --enable-version3"
}