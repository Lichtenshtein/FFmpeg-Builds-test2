#!/bin/bash

# Добавляем базовые опции конфигурации FFmpeg
ffbuild_configure "--enable-gpl --enable-version3 --disable-debug"
GIT_BRANCH="${FFMPEG_BRANCH}"
LICENSE_FILE="COPYING.GPLv3"