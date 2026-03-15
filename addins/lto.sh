#!/bin/bash

log_info "${XCLAM_MARK} LTO Addin: Enabling Link Time Optimization..."
# Флаг для FFmpeg
ffbuild_configure "--enable-lto"

export CFLAGS="${CFLAGS} -flto=auto"
export CXXFLAGS="${CXXFLAGS} -flto=auto"
export LDFLAGS="${LDFLAGS} -flto=auto"

# добавляем в аккумуляторы FFmpeg, чтобы они попали в --extra-cflags
ffbuild_cflags "-flto=auto"
ffbuild_ldflags "-flto=auto"

# для LTO нужны версии с плагинами)
export AR="${FFBUILD_CROSS_PREFIX}gcc-ar"
export NM="${FFBUILD_CROSS_PREFIX}gcc-nm"
export RANLIB="${FFBUILD_CROSS_PREFIX}gcc-ranlib"
