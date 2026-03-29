#!/bin/bash

log_info "${XCLAM_MARK} LTO Addin: Enabling Link Time Optimization..."

# Флаг для FFmpeg
ffbuild_configure() {
    echo "--enable-lto"
}
# добавляем в аккумуляторы FFmpeg, чтобы они попали в --extra-cflags
ffbuild_cflags() {
    echo "-flto=auto"
}
ffbuild_cxxflags() {
    echo "-flto=auto"
}
ffbuild_ldflags() {
    echo "-flto=auto"
}

# для LTO нужны версии с плагинами)
export AR="${FFBUILD_CROSS_PREFIX}gcc-ar"
export NM="${FFBUILD_CROSS_PREFIX}gcc-nm"
export RANLIB="${FFBUILD_CROSS_PREFIX}gcc-ranlib"