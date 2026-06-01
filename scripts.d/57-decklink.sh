#!/bin/bash

SCRIPT_REPO="https://gitlab.com/m-ab-s/decklink-headers.git"
SCRIPT_COMMIT="d841c2e7ca8e898eb5325a621975c7698f3f5dab"

ffbuild_enabled() {
    [[ $TARGET == winarm64 ]] && return 1
    [[ $TARGET == linux* ]] && return 1
    [[ $VARIANT == nonfree* ]] || return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl .
}

ffbuild_dockerbuild() {
    set -e

    mkdir -p "$INSTALL_ROOT/include"

    make PREFIX="$INSTALL_ROOT" install || return 1

    # —оздаем DeckLinkAPI_v14_2_1.h, который просто перенаправл€ет на новый DeckLinkAPI.h
    echo '#include <DeckLinkAPI.h>' > "$INSTALL_ROOT/include/DeckLinkAPI_v14_2_1.h"

    log_info "DeckLink 15.3 headers installed with FFmpeg compatibility bypass."
}

ffbuild_configure() {
    echo --enable-decklink
}

ffbuild_unconfigure() {
    echo --disable-decklink
}
