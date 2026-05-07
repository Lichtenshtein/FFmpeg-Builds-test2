#!/bin/bash

package_variant() {
    local IN="$1"
    local OUT="$2"

    log_info "Packaging variant from $IN to $OUT..."

    mkdir -p "$OUT/bin"
    if ls "$IN"/bin/*.exe >/dev/null 2>&1; then
        cp "$IN"/bin/*.exe "$OUT/bin/"
    fi

    if [ -d "$IN/share/doc/ffmpeg" ]; then
        mkdir -p "$OUT/doc"
        cp -r "$IN"/share/doc/ffmpeg/* "$OUT/doc/"
    fi

    if [ -d "$IN/share/man" ]; then
        mkdir -p "$OUT/man"
        cp -r "$IN"/share/man/* "$OUT/man/"
    fi

    if [ -d "$IN/share/ffmpeg" ]; then
        mkdir -p "$OUT/presets"
        cp "$IN"/share/ffmpeg/*.ffpreset "$OUT/presets/" 2>/dev/null || true
    fi
}
