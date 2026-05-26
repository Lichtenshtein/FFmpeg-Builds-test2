#!/bin/bash

set -e
shopt -s globstar
cd "$(dirname "$0")"

# Забираем аргументы из workflow.yaml для локального использования
TARGET="${1:-$TARGET}"
VARIANT="${2:-$VARIANT}"

# Загружаем переменные
source util/vars.sh "$TARGET" "$VARIANT" 2>&1 || {
    echo "ERROR: vars.sh failed (TARGET=$TARGET VARIANT=$VARIANT)" >&2
    exit 1
}

# build ADDINS array based on ENV VARIABLES
ADDINS=()
ADDINS_STR=""

# Check each potential addin based on ENV variables
if [[ "$USE_LTO" == "1" ]] && [[ -f "${ADDINS_DIR}/lto.sh" ]]; then
    ADDINS+=("lto")
    ADDINS_STR="${ADDINS_STR}${ADDINS_STR:+-}lto"
    log_info "${XCLAM_MARK} LTO addin enabled."
fi

if [[ "$USE_AVX512" == "1" ]] && [[ -f "${ADDINS_DIR}/avx512.sh" ]]; then
    ADDINS+=("avx512")
    ADDINS_STR="${ADDINS_STR}${ADDINS_STR:+-}avx512"
    log_info "${XCLAM_MARK} AVX512 addin enabled."
fi

if [[ "$PREFER_SHARED" == "1" ]] && [[ -f "${ADDINS_DIR}/shared.sh" ]]; then
    ADDINS+=("shared")
    ADDINS_STR="${ADDINS_STR}${ADDINS_STR:+-}shared"
    log_info "${XCLAM_MARK} SHARED addin enabled."
fi

# Allow custom addins via CUSTOM_ADDINS env var (space-separated)
if [[ -n "$CUSTOM_ADDINS" ]]; then
    for addin in $CUSTOM_ADDINS; do
        addin_path="${ADDINS_DIR}/${addin}.sh"
        if [[ -f "$addin_path" ]]; then
            ADDINS+=("$addin")
            ADDINS_STR="${ADDINS_STR}${ADDINS_STR:+-}${addin}"
            log_info "${XCLAM_MARK} Custom addin enabled: $addin"
        else
            log_warn "Custom addin not found at $addin_path"
            # exit 1
        fi
    done
fi
export ADDINS ADDINS_STR

log_info "${CHECK_MARK} Active addins: ${GREY_B}${ADDINS_STR:-none}${NC}"

# other early indications for "Run Download and Generate" build stage
[[ "$DEDUPE_FLAGS" == "1" ]]   && log_info "${XCLAM_MARK} Extended deduplication for stages collected LIBS is enabled!"
[[ "$FFMPEG_PATCHES" == "1" ]] && log_info "${XCLAM_MARK} Custom patches for FFmpeg are activated!"
[[ "$SAFE_CONFIGURE" == "1" ]] && log_info "${XCLAM_MARK} Safe FFmpeg flags configuration is enabled!"
[[ "$SKIP_FFMPEG" == "1" ]]    && log_info "${XCLAM_MARK} Component test mode activated! FFmpeg compilation will be skipped."
[[ "$USE_OPENMP" == "1" ]]     && log_info "${XCLAM_MARK} Open Multi-Processing runtime for shared-memory parallel programming is enabled!"
[[ "$SHADERC_UPDATE" == "1" ]] && log_info "${XCLAM_MARK} Shaderc dependencies will be updated from the local DEPS file."
[[ "$OLDER_FFNV" == "1" ]]     && log_info "${XCLAM_MARK} FFNVcodec sdk version 8.1 will be installed."
[[ "$DIR_NUMBERS" == "1" ]]    && log_info "${XCLAM_MARK} Script collector will ignore numbering of folders."
[[ "$BUILD_VINO" == "1" ]]     && log_info "${XCLAM_MARK} Will build OpenVINO from source. You'll gonna carry that weight..."

log_info "${START_MARK} Configuration generated. Transferring pipeline control to build_dispatcher.sh..."

# Передаем управление диспетчеру, сохраняя экспортированный ADDINS_STR
exec ./build_dispatcher.sh "$TARGET" "$VARIANT"