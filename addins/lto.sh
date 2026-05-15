#!/bin/bash

log_info "${XCLAM_MARK} LTO Addin: Enabling Link Time Optimization..."

# Флаг для FFmpeg
# --enable-lto=full (default); --enable-lto=thin (to save build time)

# disabled LTO due to critical bug in gcc-15.2; ICE (Internal Compiler Error)
# lto1: internal compiler error: in choose_baseaddr, at config/i386/i386.cc:7447
ffbuild_configure() {
    echo "--enable-lto"
}

# -ffat-lto-objects позволит библиотекам содержать как LTO-код, так и обычный объектный код. Это увеличит размер промежуточных библиотек, но сделает линковку более стабильной
# -mpreferred-stack-boundary=4
# ffbuild_cflags() {
    # echo "${USELTO} -flto-compression-level=4 -mstackrealign"
# }
# ffbuild_cxxflags() {
    # echo "${USELTO} -flto-compression-level=4 -mstackrealign"
# }
# "-fno-use-linker-plugin"
# ffbuild_ldflags() {
    # echo "${USELTO}"
# }

# для LTO нужны версии с плагинами)
# export AR="${FFBUILD_CROSS_PREFIX}gcc-ar"
# export NM="${FFBUILD_CROSS_PREFIX}gcc-nm"
# export RANLIB="${FFBUILD_CROSS_PREFIX}gcc-ranlib"

for tool in AR NM RANLIB; do
    tool_path="${!tool}"
    if ! command -v "$tool_path" &>/dev/null; then
        log_error "LTO addin: $tool not found at $tool_path"
        exit 1
    fi
done
log_info "${CHECK_MARK} LTO tools verified:\nAR=$AR\nNM=$NM\nRANLIB=$RANLIB"

if [[ "$ENABLE_SHARED" == "1" ]]; then
    log_warn "LTO + Shared builds may have linker issues on some systems. Monitor carefully."
fi