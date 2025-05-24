#!/bin/bash

SCRIPT_REPO="https://gitlab.com/m-ab-s/decklink-headers"
SCRIPT_COMMIT="1cc63fbdb06f26b39bbb85c918d863753d969ad9"

ffbuild_enabled() {
    [[ $TARGET == winarm64 ]] && return -1
    [[ $VARIANT == nonfree* ]] || return -1
    return 0
}

ffbuild_dockerbuild() {
    make PREFIX="$FFBUILD_PREFIX" install
}

ffbuild_configure() {
    echo --enable-decklink
}

ffbuild_unconfigure() {
    echo --disable-decklink
}
