#!/bin/bash
source "$(dirname "${BASH_SOURCE}")"/windows-install-shared.sh
source "$(dirname "${BASH_SOURCE}")"/defaults-gpl.sh
ffbuild_configure() {
    echo "--pkg-config-flags='' --enable-shared --disable-static --enable-gpl --enable-version3"
}