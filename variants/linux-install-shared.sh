#!/bin/bash

package_variant() {
    local IN="$1"
    local OUT="$2"

    mkdir -p "$OUT"/bin
    cp -r "$IN"/bin/* "$OUT"/bin 2>/dev/null || log_warn "Failed to copy binaries"

    # For shared builds, also copy .so files
    if [[ -d "$IN/lib" ]]; then
        find "$IN/lib" -name "*.so*" -exec cp {} "$OUT/bin/" \; 2>/dev/null || true
    fi

    mkdir -p "$OUT/doc"
    cp -r "$IN"/share/doc/ffmpeg/* "$OUT"/doc 2>/dev/null || true

    mkdir -p "$OUT/man"
    cp -r "$IN"/share/man/* "$OUT"/man 2>/dev/null || true

    mkdir -p "$OUT/presets"
    cp "$IN"/share/ffmpeg/*.ffpreset "$OUT"/presets 2>/dev/null || true
}