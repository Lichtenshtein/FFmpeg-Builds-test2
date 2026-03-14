#!/bin/bash

package_variant() {
    IN="$1"
    OUT="$2"

    mkdir -p "$OUT/bin"
    if [[ -d "$IN/bin" ]] && compgen -G "$IN/bin/*" > /dev/null; then
        cp "$IN"/bin/* "$OUT"/bin
    else
        log_warn "No files in $IN/bin to copy"
    fi

    if [[ -d "$IN/share/doc/ffmpeg" ]]; then
        mkdir -p "$OUT/doc"
        cp -r "$IN"/share/doc/ffmpeg/* "$OUT"/doc
    else
        log_warn "No doc directory found at $IN/share/doc/ffmpeg"
    fi

    if compgen -G "$IN/share/ffmpeg/*.ffpreset" > /dev/null 2>&1; then
        mkdir -p "$OUT/presets"
        cp "$IN"/share/ffmpeg/*.ffpreset "$OUT"/presets
    else
        log_warn "No .ffpreset files found in $IN/share/ffmpeg"
    fi
}
