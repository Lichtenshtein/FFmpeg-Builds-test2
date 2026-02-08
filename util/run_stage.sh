#!/bin/bash
set -e

# $1 - это полный путь к скрипту, например /builder/scripts.d/10-mingw.sh
SCRIPT_PATH="$1"

if [[ ! -f "$SCRIPT_PATH" ]]; then
    echo "Error: Script $SCRIPT_PATH not found"
    exit 1
fi

export RAW_CFLAGS="$CFLAGS"
export RAW_CXXFLAGS="$CXXFLAGS"
export RAW_LDFLAGS="$LDFLAGS"

[[ -n "$STAGE_CFLAGS" ]] && export CFLAGS="$CFLAGS $STAGE_CFLAGS"
[[ -n "$STAGE_CXXFLAGS" ]] && export CXXFLAGS="$CXXFLAGS $STAGE_CXXFLAGS"
[[ -n "$STAGE_LDFLAGS" ]] && export LDFLAGS="$LDFLAGS $STAGE_LDFLAGS"

STAGENAME="$(basename "$SCRIPT_PATH" | sed 's/.sh$//')"

mkdir -p "/build/$STAGENAME"
cd "/build/$STAGENAME"

# Поиск кэша в смонтированной папке
DL_CACHE="/root/.cache/downloads/${STAGENAME}.tar.xz"
if [[ -f "$DL_CACHE" ]]; then
    tar xaf "$DL_CACHE" -C .
fi

# Загружаем скрипт
source "$SCRIPT_PATH"

if [[ -z "$2" ]]; then
    ffbuild_dockerbuild
else
    "$2"
fi

cd /
rm -rf "/build/$STAGENAME"
