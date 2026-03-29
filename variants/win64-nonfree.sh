#!/bin/bash

source "$(dirname "${BASH_SOURCE}")"/win64-gpl.sh
ffbuild_configure() {
    echo "--enable-nonfree"
}
LICENSE_FILE=""