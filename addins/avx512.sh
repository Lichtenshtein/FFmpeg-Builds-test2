#!/bin/bash

if [[ ! "$FFBUILD_TOOLCHAIN" =~ x86_64 ]]; then
    log_warn "AVX512 addin: skipping (not x86_64 target)"
    return 0
fi

if [[ "$TARGET" == *"linux"* ]]; then
    log_warn "AVX512 addin: Linux native builds may not support skylake-avx512 on all CPUs"
fi

log_info "${XCLAM_MARK} AVX512 Addin: Enabling AVX512 Optimization..."

# Replaces -march=broadwell with AVX-512 capable target
# Broadwell does NOT support AVX-512 — use a capable arch instead
ffbuild_cflags() {
    local flags="$CFLAGS"
    # Remove any existing -march flag
    flags="${flags// -march=[^ ]*/}"
    echo "${flags} -march=skylake-avx512 -mavx512f -mavx512bw -mavx512cd -mavx512dq -mavx512vl"
}
ffbuild_cxxflags() {
    local flags="$CXXFLAGS"
    flags="${flags// -march=[^ ]*/}"
    echo "${flags} -march=skylake-avx512 -mavx512f -mavx512bw -mavx512cd -mavx512dq -mavx512vl"
}