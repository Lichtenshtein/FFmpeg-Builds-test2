#!/bin/bash

ffbuild_enabled() {
    # [[ $TARGET == win* ]] || return 1
    return 0
}

ffbuild_dockerbuild() {
    set -e
    return 0

}

ffbuild_configure() {
    echo --enable-wasapi
}

ffbuild_unconfigure() {
    echo --disable-wasapi
}
