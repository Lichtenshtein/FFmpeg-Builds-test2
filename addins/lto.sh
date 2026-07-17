#!/bin/bash

log_info "${XCLAM_MARK} LTO Addin: Enabling Link Time Optimization..."

# export HOST_CFLAGS="${HOST_CFLAGS//-ffat-lto-objects/-fno-fat-lto-objects}"

# --enable-lto=full (default); --enable-lto=thin (to save build time)
ffbuild_configure() {
    echo "--enable-lto"
}

# -ffat-lto-objects will allow libraries to contain both LTO code and regular object code. This will increase the size of intermediate libraries, but will make linking more stable.
#
# Switch GCC to the medium memory model.
# This will force the compiler to use wider addresses for jumps,
# which completely solves the lto1: internal compiler error: in choose_baseaddr problem.
# If medium doesn't help, then -mcmodel=large
#
# ${USELTO_C//-ffat-lto-objects/-fno-fat-lto-objects}

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