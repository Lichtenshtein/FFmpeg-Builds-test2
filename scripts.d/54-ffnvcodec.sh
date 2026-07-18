#!/bin/bash

SCRIPT_REPO="https://github.com/FFmpeg/nv-codec-headers.git"
SCRIPT_COMMIT="15ee32753c92faddbabbff11676779618fc6db7e"

# SCRIPT_REPO="https://github.com/FFmpeg/nv-codec-headers.git"
# SCRIPT_COMMIT="33a9ede8d9914299d9262539c576a15bd0a19621"
# SCRIPT_BRANCH="sdk/13.0"

ffbuild_enabled() {
    [[ $TARGET == winarm64 ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl
}

ffbuild_dockerbuild() {
    set -e

    make PREFIX="$FFBUILD_PREFIX" DESTDIR="$FFBUILD_DESTDIR" install || return 1

    # mkdir -p "$PC_DIR"
    # if [ -f "$PC_DIR/ffnvcodec.pc" ]; then
        # sed -i "s|^Cflags:.*|& -DCUDA_VERSION=${VER_FULL}|" "$PC_DIR/ffnvcodec.pc"
    # fi
}

ffbuild_configure() {
    # Check for the presence of clang and llvm-config on the host (in the container)
    if command -v clang &>/dev/null && command -v llvm-config &>/dev/null; then
        log_info "${CHECK_MARK} LLVM/Clang found. Enable cuda-llvm."
        echo "--enable-ffnvcodec --enable-cuda-llvm --enable-nvenc --enable-nvdec"
    else
        log_warn "LLVM/Clang not found. We use standard CUDA components."
        echo "--enable-ffnvcodec --enable-nvenc --enable-nvdec --enable-cuvid"
    fi
}

ffbuild_unconfigure() {
    echo "--disable-ffnvcodec --disable-cuda-llvm --disable-cuda --disable-nvenc --disable-nvdec --disable-cuvid"
}
