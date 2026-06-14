#!/bin/bash

SCRIPT_REPO="https://github.com/FFmpeg/nv-codec-headers.git"
SCRIPT_COMMIT="1b5a81ada8874efb2af0534ffe74049c557e212d"

# SCRIPT_REPO="https://github.com/FFmpeg/nv-codec-headers.git"
# SCRIPT_COMMIT="33a9ede8d9914299d9262539c576a15bd0a19621"
# SCRIPT_BRANCH="sdk/13.0"

# not supported anymore
SCRIPT_REPO4="https://github.com/FFmpeg/nv-codec-headers.git"
SCRIPT_COMMIT4="09e12e3d803ce79c327a9709233e8cd858e59d9e"
SCRIPT_BRANCH4="sdk/8.1"

# export SKIP_POST_PC_PATCH=1

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

    if [[ "${OLDER_FFNV}" == "1" ]]; then
        cd ffnvcodec4
    else
        cd ffnvcodec
    fi

    # ffnvcodec - это просто заголовки, Makefile простой.
    make PREFIX="$FFBUILD_PREFIX" DESTDIR="$FFBUILD_DESTDIR" install || return 1

    mkdir -p "$PC_DIR"
    if [ -f "$PC_DIR/ffnvcodec.pc" ]; then
        sed -i "s|^Cflags:.*|& -I\${includedir}/ffnvcodec|" "$PC_DIR/ffnvcodec.pc"
        log_info "Cflags paths have been updated."
    fi
}

ffbuild_configure() {
    # Проверяем наличие clang и llvm-config на хосте (в контейнере)
    if command -v clang &>/dev/null && command -v llvm-config &>/dev/null; then
        log_info "${CHECK_MARK} LLVM/Clang found. Enable cuda-llvm."
        echo "--enable-ffnvcodec --enable-cuda-llvm"
    else
        log_warn "LLVM/Clang not found. We use standard CUDA components."
        echo "--enable-ffnvcodec --enable-cuda --enable-nvenc --enable-nvdec --enable-cuvid"
    fi
}

ffbuild_unconfigure() {
    echo "--disable-ffnvcodec --disable-cuda-llvm --disable-cuda --disable-nvenc --disable-nvdec --disable-cuvid"
}
