#!/bin/bash
source "$(dirname "$BASH_SOURCE")"/linux-install-static.sh
source "$(dirname "$BASH_SOURCE")"/defaults-gpl.sh
ffbuild_configure() {
    echo "--pkg-config-flags='--static' --disable-shared --enable-static --enable-gpl --enable-version3"
}