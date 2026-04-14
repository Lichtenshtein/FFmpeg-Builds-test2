#!/bin/bash

SCRIPT_REPO="https://github.com/FFmpeg/nv-codec-headers.git"
SCRIPT_COMMIT="876af32a202d0de83bd1d36fe74ee0f7fcf86b0d"

SCRIPT_REPO4="https://github.com/FFmpeg/nv-codec-headers.git"
SCRIPT_COMMIT4="9934f17316b66ce6de12f3b82203a298bc9351d8"
SCRIPT_BRANCH4="sdk/12.2"

ffbuild_enabled() {
    [[ $TARGET == winarm64 ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl ffnvcodec
    echo "git-mini-clone \"$SCRIPT_REPO4\" \"$SCRIPT_COMMIT4\" ffnvcodec4"
}

ffbuild_dockerbuild() {
    set -e

    cd ffnvcodec4

    # ffnvcodec - это просто заголовки, Makefile простой.
    make PREFIX="$FFBUILD_PREFIX" DESTDIR="$FFBUILD_DESTDIR" install || return 1
}

ffbuild_configure() {
    echo --enable-ffnvcodec --enable-cuda-llvm
}

ffbuild_unconfigure() {
    echo --disable-ffnvcodec --disable-cuda-llvm
}
