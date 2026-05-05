#!/bin/bash

log_info "${XCLAM_MARK} LTO Addin: Enabling Link Time Optimization..."

# Флаг для FFmpeg
# --enable-lto=full (default); --enable-lto=thin (to save build time)
ffbuild_configure() {
    echo "--enable-lto"
}
# добавляем в аккумуляторы FFmpeg, чтобы они попали в --extra-cflags
# -ffat-lto-objects позволит библиотекам содержать как LTO-код, так и обычный объектный код. Это увеличит размер промежуточных библиотек, но сделает линковку более стабильной
ffbuild_cflags() {
    echo "-flto=1 -ffat-lto-objects"
}
ffbuild_cxxflags() {
    echo "-flto=1 -ffat-lto-objects"
}
ffbuild_ldflags() {
    echo "-flto=1 -ffat-lto-objects"
}

# для LTO нужны версии с плагинами)
export AR="${FFBUILD_CROSS_PREFIX}gcc-ar"
export NM="${FFBUILD_CROSS_PREFIX}gcc-nm"
export RANLIB="${FFBUILD_CROSS_PREFIX}gcc-ranlib"

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