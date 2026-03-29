#!/bin/bash

log_info "${XCLAM_MARK} AVX512 Addin: Enabling AVX512 Optimization..."

# Replaces -march=broadwell with AVX-512 capable target
# Broadwell does NOT support AVX-512 — use a capable arch instead
ffbuild_cflags() {
    echo "${CFLAGS/-march=${CPU_ARCH}/-march=skylake-avx512} -mavx512f -mavx512bw -mavx512cd -mavx512dq -mavx512vl"
}
ffbuild_cxxflags() {
    echo "${CXXFLAGS/-march=${CPU_ARCH}/-march=skylake-avx512} -mavx512f -mavx512bw -mavx512cd -mavx512dq -mavx512vl"
}