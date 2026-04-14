#!/bin/bash

SCRIPT_SKIP="1"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerdl() {
    true
}

ffbuild_dockerbuild() {
    set -e
    mkdir -p "$FFBUILD_DESTPREFIX"

    if [[ "${PREFER_SHARED}" != "1" ]]; then
        if [[ $TARGET == linux* ]]; then
            rm "$FFBUILD_DESTPREFIX"/lib/lib*.so* || true
            rm "$FFBUILD_DESTPREFIX"/lib/*.la || true
        fi
    fi
}
