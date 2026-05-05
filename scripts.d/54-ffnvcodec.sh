#!/bin/bash

SCRIPT_REPO="https://github.com/FFmpeg/nv-codec-headers.git"
SCRIPT_COMMIT="33a9ede8d9914299d9262539c576a15bd0a19621"

SCRIPT_REPO2="https://github.com/FFmpeg/nv-codec-headers.git"
SCRIPT_COMMIT2="9934f17316b66ce6de12f3b82203a298bc9351d8"
SCRIPT_BRANCH2="sdk/12.2"

# SCRIPT_REPO4="https://github.com/FFmpeg/nv-codec-headers.git"
# SCRIPT_COMMIT4="09e12e3d803ce79c327a9709233e8cd858e59d9e"
# SCRIPT_BRANCH4="sdk/8.1"

# export SKIP_POST_PATCH=1

ffbuild_enabled() {
    [[ $TARGET == winarm64 ]] && return 1
    return 0
}

ffbuild_dockerdl() {
    default_dl ffnvcodec
    echo "git-mini-clone \"$SCRIPT_REPO2\" \"$SCRIPT_COMMIT2\" ffnvcodec2"
    # echo "git-mini-clone \"$SCRIPT_REPO4\" \"$SCRIPT_COMMIT4\" ffnvcodec4"
}

ffbuild_dockerbuild() {
    set -e

    if [[ "${OLDER_FFNV}" == "1" ]]; then
        cd ffnvcodec4
    else
        cd ffnvcodec2
    fi

    # ffnvcodec - это просто заголовки, Makefile простой.
    make PREFIX="$FFBUILD_PREFIX" DESTDIR="$FFBUILD_DESTDIR" install || return 1

    # Fallback для stdbit.h (C23), если компилятор его не находит
    # Проверяем через сам компилятор, видит ли он файл в своих путях
    if ! echo "#include <stdbit.h>" | $CC -E - >/dev/null 2>&1; then
        log_warn "stdbit.h not found in default paths. Creating a fallback stub..."
        mkdir -p "$INSTALL_ROOT/include"
        # Минимально необходимый контент для FFmpeg (обертки над built-ins)
        cat <<EOF > "$INSTALL_ROOT/include/stdbit.h"
#ifndef _STDBIT_H
#define _STDBIT_H
#define __STDC_VERSION_STDBIT_H__ 202311L
#define stdc_count_ones(x) __builtin_popcountll((unsigned long long)(x))
#define stdc_trailing_zeros(x) __builtin_ctzll((unsigned long long)(x))
#define stdc_leading_zeros(x) __builtin_clzll((unsigned long long)(x))
#endif
EOF
    else
        log_info "stdbit.h is natively supported by $CC, no stub needed."
    fi
}

ffbuild_configure() {
    echo --enable-ffnvcodec --enable-cuda-llvm
}

ffbuild_unconfigure() {
    echo --disable-ffnvcodec --disable-cuda-llvm
}
