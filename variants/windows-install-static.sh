#!/bin/bash

package_variant() {
    IN="$1"
    OUT="$2"

    mkdir -p "$OUT"/bin
    if [[ -d "$IN/bin" ]] && compgen -G "$IN/bin/*" > /dev/null; then
        cp "$IN"/bin/* "$OUT"/bin
    else
        log_warn "No files in $IN/bin to copy"
    fi

    mkdir -p "$OUT/doc"
    cp -r "$IN"/share/doc/ffmpeg/* "$OUT"/doc

    mkdir -p "$OUT/presets"
    cp "$IN"/share/ffmpeg/*.ffpreset "$OUT"/presets
}
