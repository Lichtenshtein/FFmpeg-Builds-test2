#!/bin/bash

log_info "${XCLAM_MARK} LTO Addin: Enabling Link Time Optimization..."

# a hook announcing that we're at the final stage
export FFMPEG_BUILD_STAGE="1"
export STAGENAME="FFmpeg"

if declare -F apply_lto_policy >/dev/null; then
    apply_lto_policy
fi

# Флаг для FFmpeg
# --enable-lto=full (default); --enable-lto=thin (to save build time)
ffbuild_configure() {
    echo "--enable-lto"
}

# -ffat-lto-objects позволит библиотекам содержать как LTO-код, так и обычный объектный код. Это увеличит размер промежуточных библиотек, но сделает линковку более стабильной
ffbuild_cflags() {
    echo "${USELTO}${USELTO_C} -mstackrealign"
}
ffbuild_cxxflags() {
    echo "${USELTO}${USELTO_C} -mstackrealign"
}
ffbuild_ldflags() {
    echo "${USELTO}"
}

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