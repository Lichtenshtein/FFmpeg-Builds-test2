#!/bin/bash

ffbuild_configure() {
    echo "--enable-gpl --enable-version3 --disable-debug"
}
GIT_BRANCH="${FFMPEG_BRANCH}"
LICENSE_FILE="COPYING.GPLv3"