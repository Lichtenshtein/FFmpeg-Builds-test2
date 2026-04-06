#!/bin/bash

source "$(dirname "${BASH_SOURCE}")"/windows-install-static.sh
source "$(dirname "${BASH_SOURCE}")"/defaults-gpl.sh

ffbuild_configure() {
    echo "--enable-nonfree"
}

LICENSE_FILE=""