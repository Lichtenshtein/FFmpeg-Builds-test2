#!/bin/bash

package_variant() {
    IN="$1"
    OUT="$2"

    mkdir -p "$OUT/bin"
    if [[ -d "$IN/bin" ]] && [[ -n "$(find "$IN/bin" -maxdepth 1 -type f 2>/dev/null)" ]]; then
        cp "$IN"/bin/* "$OUT"/bin 2>/dev/null || log_warn "Failed to copy binaries"
    else
        log_warn "No files in $IN/bin to copy"
    fi

    # For shared builds, also copy DLLs
    if [[ -d "$IN/bin" ]]; then
        find "$IN/bin" -name "*.dll" -exec cp {} "$OUT/bin/" \; 2>/dev/null || true
    fi

    if [[ -d "$IN/share/doc/ffmpeg" ]]; then
        mkdir -p "$OUT/doc"
        cp -r "$IN"/share/doc/ffmpeg/* "$OUT"/doc 2>/dev/null || true
    fi

    if [[ -d "$IN/share/ffmpeg" ]] && [[ -n "$(find "$IN/share/ffmpeg" -maxdepth 1 -name "*.ffpreset" 2>/dev/null)" ]]; then
        mkdir -p "$OUT/presets"
        cp "$IN"/share/ffmpeg/*.ffpreset "$OUT"/presets 2>/dev/null || true
    fi
}