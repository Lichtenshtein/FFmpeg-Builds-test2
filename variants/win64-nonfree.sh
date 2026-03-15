#!/bin/bash
source "$(dirname "${BASH_SOURCE}")"/win64-gpl.sh
ffbuild_configure "--enable-nonfree"
LICENSE_FILE=""
