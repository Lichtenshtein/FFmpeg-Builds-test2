#!/bin/bash

SCRIPT_REPO="https://gitlab.com/m-ab-s/decklink-headers.git"
SCRIPT_COMMIT="1cc63fbdb06f26b39bbb85c918d863753d969ad9"

ffbuild_enabled() {
    # [[ $TARGET == winarm64 ]] && return -1
    # [[ $TARGET == linux* ]] && return -1
    # [[ $VARIANT == nonfree* ]] || return -1
    return 0
}

ffbuild_dockerdl() {
    echo "git-mini-clone \"$SCRIPT_REPO\" \"$SCRIPT_COMMIT\" ."
}

ffbuild_dockerbuild() {
    # Создаем папку заранее, так как Decklink Makefile иногда капризен
    mkdir -p "$FFBUILD_DESTPREFIX/include"
    # Передаем префикс правильно
    make PREFIX="$FFBUILD_DESTPREFIX" install
}

ffbuild_configure() {
    echo --enable-decklink
}

ffbuild_unconfigure() {
    echo --disable-decklink
}
