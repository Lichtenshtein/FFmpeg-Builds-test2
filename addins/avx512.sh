#!/bin/bash

# Replaces -march=broadwell with AVX-512 capable target
# Broadwell does NOT support AVX-512 — use a capable arch instead
FF_CFLAGS="-mavx512f -mavx512bw -mavx512cd -mavx512dq -mavx512vl"
FF_CXXFLAGS="-mavx512f -mavx512bw -mavx512cd -mavx512dq -mavx512vl"

# Override CFLAGS march for component builds too
export CFLAGS="${CFLAGS/-march=broadwell/-march=skylake-avx512}"
export CXXFLAGS="${CXXFLAGS/-march=broadwell/-march=skylake-avx512}"
