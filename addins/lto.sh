#!/bin/bash

log_info "${XCLAM_MARK} LTO Addin: Enabling Link Time Optimization..."

# Флаг для FFmpeg
# --enable-lto=full (default); --enable-lto=thin (to save build time)
ffbuild_configure() {
    echo "--enable-lto"
}

# -ffat-lto-objects позволит библиотекам содержать как LTO-код, так и обычный объектный код. Это увеличит размер промежуточных библиотек, но сделает линковку более стабильной
# ${USELTO_C//-ffat-lto-objects/-fno-fat-lto-objects} 
# Переключаем GCC на среднюю модель памяти. 
# Это заставит компилятор использовать более широкие адреса для переходов, 
# что полностью решает проблему lto1: internal compiler error: in choose_baseaddr
# Если medium не поможет то -mcmodel=large
ffbuild_cflags() {
    echo "${USELTO}${USELTO_C} -mcmodel=medium -mstackrealign"
}
ffbuild_cxxflags() {
    echo "${USELTO}${USELTO_C} -mcmodel=medium -mstackrealign"
}
ffbuild_ldflags() {
    echo "${USELTO}${USELTO_L}"
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